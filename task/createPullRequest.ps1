$TLS12Protocol = [System.Net.SecurityProtocolType] 'Ssl3 , Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $TLS12Protocol

function RunTask {
    [CmdletBinding()]
    Param
    (
        [string]$sourceBranch,
        [string]$targetBranch,
        [string]$title,
        [string]$description,
        [string]$reviewers,
        [string]$tags,
        [bool]$isDraft,
        [bool]$autoComplete,
        [string]$mergeStrategy,
        [bool]$deleteSource,
        [System.ObsoleteAttribute("Use deleteSource Parameter")]
        [bool]$deleteSourch,
        [string]$commitMessage,
        [bool]$transitionWorkItems,
        [bool]$linkWorkItems,
        [string]$teamProject,
        [string]$repositoryName,
        [string]$githubRepository,
        [bool]$passPullRequestIdBackToADO,
        [bool]$isForked,
        [bool]$bypassPolicy,
        [string]$bypassReason, 
        [bool]$alwaysCreatePR,
        [bool]$githubAutoMerge,
        [string]$githubMergeCommitTitle,
        [string]$githubMergeCommitMessage,
        [string]$githubMergeStrategy,
        [bool]$githubDeleteSourceBranch
    )

    Trace-VstsEnteringInvocation $MyInvocation
    try {
        # Get inputs
        $sourceBranch = Get-VstsInput -Name 'sourceBranch' -Require
        $targetBranch = Get-VstsInput -Name 'targetBranch' -Require
        $title = Get-VstsInput -Name 'title' -Require
        $description = Get-VstsInput -Name 'description'
        $reviewers = Get-VstsInput -Name 'reviewers'
        $tags = Get-VstsInput -Name 'tags'
        $repoType = Get-VstsInput -Name 'repoType' -Require
        $isDraft = Get-VstsInput -Name 'isDraft' -AsBool
        $autoComplete = Get-VstsInput -Name 'autoComplete' -AsBool
        $mergeStrategy = Get-VstsInput -Name 'mergeStrategy' 
        $deleteSourch = Get-VstsInput -Name 'deleteSourch' -AsBool
        $deleteSource = Get-VstsInput -Name 'deleteSource' -AsBool
        $commitMessage = Get-VstsInput -Name 'commitMessage' 
        $transitionWorkItems = Get-VstsInput -Name 'transitionWorkItems' -AsBool
        $linkWorkItems = Get-VstsInput -Name 'linkWorkItems' -AsBool
        $teamProject = Get-VstsInput -Name 'projectId' 
        $repositoryName = Get-VstsInput -Name 'gitRepositoryId'
        $githubRepository = Get-VstsInput -Name 'githubRepository'
        $passPullRequestIdBackToADO = Get-VstsInput -Name 'passPullRequestIdBackToADO' -AsBool
        $isForked = Get-VstsInput -Name 'isForked' -AsBool
        $bypassPolicy = Get-VstsInput -Name 'bypassPolicy' -AsBool
        $bypassReason = Get-VstsInput -Name 'bypassReason'
        $alwaysCreatePR = Get-VstsInput -Name 'alwaysCreatePr' -AsBool
        $githubAutoMerge = Get-VstsInput -Name 'githubAutoMerge' -AsBool
        $githubMergeCommitTitle = Get-VstsInput -Name 'githubMergeCommitTitle'
        $githubMergeCommitMessage = Get-VstsInput -Name 'githubMergeCommitMessage'
        $githubMergeStrategy = Get-VstsInput -Name 'githubMergeStrategy'
        $githubDeleteSourceBranch = Get-VstsInput -Name 'githubDeleteSourceBranch' -AsBool

        $deleteSourch = $deleteSource

        $global:token = (Get-VstsEndpoint -Name SystemVssConnection -Require).auth.parameters.AccessToken

        if ($repositoryName -eq "" -or $repositoryName -eq "currentBuild" -or $isForked -eq $True) {
            $forkedRepoName = $repositoryName 
            $teamProject = $env:System_TeamProject
            $repositoryName = $env:Build_Repository_Name
        }

        # Remove spcaes out of Repo Name
        $repositoryName = $repositoryName.Replace(" ", "%20")
        $targetBranches = $targetBranch

        # Init pullRequestIds
        [array]$global:pullRequestIds

        # If is multi-target branch, like master;feature
        $targetBranches = $targetBranch.Split(';') # will create array with single element even if no ';'

        # If is multi-target branch, like release/*
        if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($targetBranch)) {
            if ($repoType -eq "Azure DevOps") {
                $url = "$env:System_TeamFoundationCollectionUri$($teamProject)/_apis/git/repositories/$($repositoryName)/refs?api-version=4.0"
                $header = @{ Authorization = "Bearer $global:token" }
                $refs = Invoke-RestMethod -Uri $url -Method Get -Headers $header -ContentType "application/json"
                $targetBranches = $refs.value.name.Where({
                    $branch = $_
                    $targetBranches.Where({$branch -like $_ -or $branch -like "refs/heads/${_}"}).Count -ne 0
                })
            }
            else {
                $serviceNameInput = Get-VstsInput -Name ConnectedServiceNameSelector -Default 'githubEndpoint'
                $serviceName = Get-VstsInput -Name $serviceNameInput -Default (Get-VstsInput -Name DeploymentEnvironmentName)
                if (!$serviceName) {
                    # Let the task SDK throw an error message if the input isn't defined.
                    Get-VstsInput -Name $serviceNameInput -Require
                }
                $endpoint = Get-VstsEndpoint -Name $serviceName -Require
                $token = $endpoint.Auth.Parameters.accessToken
                $repoUrlSplitted = $githubRepository.Split('/')
                $owner = $repoUrlSplitted.Split('/')[0]
                $repo = $repoUrlSplitted.Split('/')[1]
                $url = "https://api.github.com/repos/$owner/$repo/branches"
                $header = @{ Authorization = ("token $token") ; Accept = "application/vnd.github.shadow-cat-preview+json" }
                $branches = Invoke-RestMethod -Uri $url -Method Get -ContentType "application/json" -Headers $header
                $targetBranches = $branches.name.Where({
                    $branch = $_
                    $targetBranches.Where({$branch -like $_ -or $branch -like "refs/heads/${_}"}).Count -ne 0
                })
            }
        }

        foreach($branch in $targetBranches) {
            $pullRequestTitle = $title.Replace('[BRANCH_NAME]', $branch.Replace('refs/heads/',''))

            CreatePullRequest -teamProject $teamProject -repositoryName $repositoryName -sourceBranch $sourceBranch -targetBranch $branch `
            -title $pullRequestTitle -description $description -reviewers $reviewers -repoType $repoType -isDraft $isDraft `
            -autoComplete $autoComplete -mergeStrategy $mergeStrategy -deleteSourch $deleteSourch -commitMessage $commitMessage `
            -transitionWorkItems $transitionWorkItems -linkWorkItems $linkWorkItems -githubRepository $githubRepository `
            -passPullRequestIdBackToADO $passPullRequestIdBackToADO -isForked $isForked -bypassPolicy $bypassPolicy -bypassReason $bypassReason `
            -tags $tags -alwaysCreatePR $alwaysCreatePR -githubAutoMerge $githubAutoMerge -githubMergeCommitTitle $githubMergeCommitTitle `
            -githubMergeCommitMessage $githubMergeCommitMessage -githubMergeStrategy $githubMergeStrategy -githubDeleteSourceBranch $githubDeleteSourceBranch
        }

        if ($passPullRequestIdBackToADO) {
            # Pass pullRequestId back to Azure DevOps for consumption by other pipeline tasks
            write-host "##vso[task.setvariable variable=pullRequestId]$(($global:pullRequestIds -join ';').TrimEnd(';'))"
        }
    }

    finally {
        Trace-VstsLeavingInvocation $MyInvocation
    }
}

function CreatePullRequest() {
    [CmdletBinding()]
    Param
    (
        [string]$repoType,
        [string]$sourceBranch,
        [string]$targetBranch,
        [string]$title,
        [string]$description,
        [string]$reviewers,
        [bool]$isDraft,
        [bool]$autoComplete,
        [string]$mergeStrategy,
        [bool]$deleteSourch,
        [string]$commitMessage,
        [bool]$transitionWorkItems,
        [bool]$linkWorkItems,
        [string]$teamProject,
        [string]$repositoryName,
        [string]$githubRepository,
        [bool]$passPullRequestIdBackToADO,
        [bool]$isForked,
        [bool]$bypassPolicy,
        [string]$bypassReason, 
        [bool]$alwaysCreatePR,
        [string]$tags,
        [bool]$githubAutoMerge,
        [string]$githubMergeCommitTitle,
        [string]$githubMergeCommitMessage,
        [string]$githubMergeStrategy,
        [bool]$githubDeleteSourceBranch
    )

    if ($repoType -eq "Azure DevOps") { 
        CreateAzureDevOpsPullRequest -teamProject $teamProject -repositoryName $repositoryName -sourceBranch $sourceBranch `
        -targetBranch $targetBranch -title $title -description $description -reviewers $reviewers -isDraft $isDraft `
        -autoComplete $autoComplete -mergeStrategy $mergeStrategy -deleteSourch $deleteSourch -commitMessage $commitMessage `
        -transitionWorkItems $transitionWorkItems -linkWorkItems $linkWorkItems -passPullRequestIdBackToADO $passPullRequestIdBackToADO `
        -isForked $isForked -bypassPolicy $bypassPolicy -bypassReason $bypassReason -tags $tags -alwaysCreatePR $alwaysCreatePR
    }
        
    else {
        # Is GitHub repository
        CreateGitHubPullRequest -sourceBranch $sourceBranch -targetBranch $targetBranch -title $title -description $description `
        -reviewers $reviewers -isDraft $isDraft -githubRepository $githubRepository -passPullRequestIdBackToADO $passPullRequestIdBackToADO `
        -tags $tags -githubAutoMerge $githubAutoMerge -githubMergeCommitTitle $githubMergeCommitTitle `
        -githubMergeCommitMessage $githubMergeCommitMessage -githubMergeStrategy $githubMergeStrategy -githubDeleteSourceBranch $githubDeleteSourceBranch
    }
}

function CreateGitHubPullRequest() {
    [CmdletBinding()]
    Param
    (
        [string]$repoType,
        [string]$sourceBranch,
        [string]$targetBranch,
        [string]$title,
        [string]$description,
        [string]$reviewers,
        [bool]$isDraft,
        [string]$githubRepository,
        [bool]$passPullRequestIdBackToADO,
        [string]$tags,
        [bool]$githubAutoMerge,
        [string]$githubMergeCommitTitle,
        [string]$githubMergeCommitMessage,
        [string]$githubMergeStrategy,
        [bool]$githubDeleteSourceBranch
    )

    Write-Host "The repository is: $githubRepository"
    Write-Host "The Source Branch is: $sourceBranch"
    Write-Host "The Target Branch is: $targetBranch"
    Write-Host "The Title is: $title"
    Write-Host "The Description is: $description"
    Write-Host "The reviewers are: $reviewers"
    Write-Host "Is Draft Pull Request: $isDraft"
    Write-Host "Auto merge?: $githubAutoMerge"

    $serviceNameInput = Get-VstsInput -Name ConnectedServiceNameSelector -Default 'githubEndpoint'
    $serviceName = Get-VstsInput -Name $serviceNameInput -Default (Get-VstsInput -Name DeploymentEnvironmentName)
    if (!$serviceName) {
        # Let the task SDK throw an error message if the input isn't defined.
        Get-VstsInput -Name $serviceNameInput -Require
    }

    $endpoint = Get-VstsEndpoint -Name $serviceName -Require
    $token = $endpoint.Auth.Parameters.accessToken
    $repoUrlSplitted = $githubRepository.Split('/')
    $owner = $repoUrlSplitted.Split('/')[0]
    $repo = $repoUrlSplitted.Split('/')[1]
    $url = "https://api.github.com/repos/$owner/$repo/pulls"
    $body = @{
        head   = "$sourceBranch"
        base   = "$targetBranch"
        title  = "$title"
        body   = "$description"
    }

    # Add the draft property only if is true and not add draft=false when it's false because there are github repos that doesn't support draft PR. see github issue #13
    if ($isDraft -eq $True) {
        $body.Add("draft" , $isDraft)
    }

    $jsonBody = ConvertTo-Json $body
    Write-Debug $jsonBody
    $header = @{ Authorization = ("token $token") ; Accept = "application/vnd.github.shadow-cat-preview+json" }
    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json;charset=UTF-8" -Headers $header -Body $jsonBody
        if ($Null -ne $response -and $response.number -ne "") {
            # If the response not null - the create PR succeeded
            Write-Host "*************************"
            Write-Host "******** Success ********"
            Write-Host "*************************"
            Write-Host "Pull Request $($response.number) created."

            if ($passPullRequestIdBackToADO) {
                $global:pullRequestIds += "$($response.number);"
            }

            # If the reviewers not null so add the reviewers to the PR
            if ($reviewers -ne "") {
                CreateGitHubReviewers -reviewers $reviewers -token $token -prNumber $response.number -repo $githubRepository
            }

            # If the tags not null so add the reviewers to the PR
            if ($tags -ne "") {
                CreateGitHubLabels -labels $tags -token $token -prNumber $response.number -repo $githubRepository
            }

            if ($githubAutoMerge) {
                GitHubAutoMerge -token $token -prNumber $response.number -repo $githubRepository -commitMessage $githubMergeCommitMessage `
                -commitTitle $githubMergeCommitTitle -mergeStrategy $githubMergeStrategy -deleteSource $githubDeleteSourceBranch `
                -sourceBranch $sourceBranch
            }
        }
        else {
            Write-Error "Failed to create Pull Request: $response"
        }
    }

    catch {
        Write-Error $_
        Write-Error $_.Exception.Message
    }
}

function CreateGitHubReviewers() {
    [CmdletBinding()]
    Param
    (
        [string]$reviewers,
        [string]$token,
        [string]$prNumber,
        [string]$repo
    )
    $split = $reviewers.Split(';').Trim()
    $repoUrl = $repo
    $owner = $repoUrl.Split('/')[0]
    $repo = $repoUrl.Split('/')[1]
    $url = "https://api.github.com/repos/$owner/$repo/pulls/$prNumber/requested_reviewers"
    $body = @{
        owner = $owner
        repo = $repo
        pull_number = $prNumber
        reviewers = @()
    }
    ForEach ($reviewer in $split) {
        $body.reviewers += $reviewer
    }
    $jsonBody = $body | ConvertTo-Json
    Write-Debug $jsonBody
    $header = @{ Authorization = ("token $token") ; Accept = "application/vnd.github.v3+json" }
    try {
        Write-Host "Add reviewers to the Pull Request..."
        $response = Invoke-RestMethod -Uri $url -Method Post -ContentType application/json -Headers $header -Body $jsonBody
        if ($Null -ne $response) {
            # If the response not null - the create PR succeeded
            Write-Host "******** Success ********"
            Write-Host "Reviewers were added to PR #$prNumber"
        }
    }

    catch {
        Write-Error $_
        Write-Error $_.Exception.Message
    }
}

function CreateGitHubLabels() {
    [CmdletBinding()]
    Param
    (
        [string]$labels,
        [string]$token,
        [string]$prNumber,
        [string]$repo
    )
    $labels = $labels.Split(';').Trim()
    $repoUrl = $repo
    $owner = $repoUrl.Split('/')[0]
    $repo = $repoUrl.Split('/')[1]
    $url = "https://api.github.com/repos/$owner/$repo/issues/$prNumber/labels"
    
    $body = @{
        labels = ""
    }
    
    if ($tags -ne "") {
        $tagList = $tags.Split(';')
        $tagsBody = @()
        foreach($tag in $tagList)
        {
            $tagsBody += $tag  
        }
        $body.labels = $tagsBody
    }
    $jsonBody = $body | ConvertTo-Json
    Write-Debug $jsonBody
    $header = @{ Authorization = ("token $token") ; Accept = "application/vnd.github.v3+json" }
    try {
        Write-Host "Add labels to the Pull Request..."
        $response = Invoke-RestMethod -Uri $url -Method Post -ContentType application/json -Headers $header -Body $jsonBody
        if ($Null -ne $response) {
            Write-Host "******** Success ********"
            Write-Host "Labels were added to PR #$prNumber"
        }
    }

    catch {
        Write-Error $_
        Write-Error $_.Exception.Message
    }
}

function GitHubAutoMerge {
    [CmdletBinding()]
    Param
    (
        [string]$prNumber,
        [string]$mergeStrategy,
        [string]$commitTitle,
        [string]$commitMessage,
        [string]$repositoryName,
        [string]$token,
        [bool]$deleteSource,
        [string]$sourceBranch
    )

    $owner = $repositoryName.Split('/')[0]
    $repo = $repositoryName.Split('/')[1]
    $url = "https://api.github.com/repos/$owner/$repo/pulls/$prNumber/merge"

    $body = @{
        commit_title = "$commitTitle"
        commit_message = "$commitMessage"
        merge_method = "$mergeStrategy"
    }    

    $jsonBody = $body | ConvertTo-Json
    Write-Debug $jsonBody
    $header = @{ Authorization = ("token $token") ; Accept = "application/vnd.github.v3+json" }
    try {
        Write-Host "Merging the Pull Request..."
        Invoke-RestMethod -Uri $url -Method Put -ContentType application/json -Headers $header -Body $jsonBody
        Write-Host "******** Merge is succeed ********"
    }

    catch {
        Write-Error $_
        Write-Error $_.Exception.Message
    }
    if($deleteSource)
    {
        Write-Host "Deleting the source branch..."
        $url = "https://api.github.com/repos/$owner/$repo/git/refs/heads/$sourceBranch"
        try {
        Invoke-RestMethod -Uri $url -Method DELETE -ContentType application/json -Headers $header
        Write-Host "******** The branch $sourceBranch is deleted ********"
        }

        catch {
            Write-Error $_
            Write-Error $_.Exception.Message
        }
    }
}


function CreateAzureDevOpsPullRequest() {
    [CmdletBinding()]
    Param
    (
        [string]$sourceBranch,
        [string]$targetBranch,
        [string]$title,
        [string]$description,
        [string]$reviewers,
        [bool]$isDraft,
        [bool]$autoComplete,
        [string]$mergeStrategy,
        [bool]$deleteSourch,
        [string]$commitMessage,
        [bool]$transitionWorkItems,
        [bool]$linkWorkItems,
        [string]$teamProject,
        [string]$repositoryName,
        [bool]$passPullRequestIdBackToADO,
        [bool]$isForked,
        [bool]$bypassPolicy,
        [string]$bypassReason, 
        [bool]$alwaysCreatePR,
        [string]$tags
    )

    if (!$sourceBranch.Contains("refs")) {
        $sourceBranch = "refs/heads/$sourceBranch"
    }
    
    if (!$targetBranch.Contains("refs")) {
        $targetBranch = "refs/heads/$targetBranch"
    }

    Write-Host "The repository is: $repositoryName"
    Write-Host "The Source Branch is: $sourceBranch"
    Write-Host "The Target Branch is: $targetBranch"
    Write-Host "The Title is: $title"
    Write-Host "The Description is: $description"
    Write-Host "The Reviewers are: $reviewers"
    Write-Host "The tags are: $tags"
    Write-Host "Is Draft Pull Request: $isDraft"
    Write-Host "Auto-Complete: $autoComplete"
    Write-Host "Link Work Items: $linkWorkItems"
    Write-Host "Bypass: $bypassPolicy"
    Write-Host "Bypass Reason: $bypassReason"
    Write-Host "DeleteSourceBranch ist set to: $deleteSourch"

    if($isForked -eq $False) {
        $changesExist = CheckIfThereAreChanges -sourceBranch $sourceBranch -targetBranch $targetBranch -alwaysCreatePR $alwaysCreatePR
        if($changesExist -eq "false")
        {
            return
        }
    }

    $body = @{
        sourceRefName = "$sourceBranch"
        targetRefName = "$targetBranch"
        title         = "$title"
        description   = "$description"
        reviewers     = ""
        labels        = ""
        isDraft       = "$isDraft"
        WorkItemRefs  = ""
        forkSource    = ""
    }

    if ($reviewers -ne "") {
        $usersId = GetReviewerId -reviewers $reviewers
        $body.reviewers = @( $usersId )
        Write-Host "The reviewers are: $($reviewers.Split(';'))"
    }

    if ($tags -ne "") {
        $tagList = $tags.Split(';')
        $tagsBody = @()
        foreach($tag in $tagList)
        {
            $tagsBody += @{ 
                name = "$tag"
            }
        
        }
        $body.labels = $tagsBody
    }

    if ($linkWorkItems -eq $True) {
        $workItems = GetLinkedWorkItems -teamProject $teamProject -repositoryName $repositoryName -sourceBranch $sourceBranch.Remove(0, 11) -targetBranch $targetBranch.Remove(0, 11)
        $body.WorkItemRefs = @( $workItems )
    }

    $header = @{ Authorization = "Bearer $global:token" }

    if ($isForked -eq $True) {
        $url = "$env:System_TeamFoundationCollectionUri$($teamProject)/_apis/git/repositories/$($forkedRepoName)?api-version=5.0"
        $response =  Invoke-RestMethod -Uri $url -Method Get -Headers $header -ContentType "application/json;charset=UTF-8"
        $forkedRepoId = $response.id
        $body.forkSource = @{ repository = @{
                id = $forkedRepoId
        } } 
    }

    $jsonBody = ConvertTo-Json $body
    Write-Host $jsonBody
    $apiVersion = if (($env:System_TeamFoundationCollectionUri -imatch "visualstudio\.com") -or ($env:System_TeamFoundationCollectionUri -imatch "dev\.azure\.com")) { "7.0" } else { "4.0" }
    $url = "$env:System_TeamFoundationCollectionUri$($teamProject)/_apis/git/repositories/$($repositoryName)/pullrequests?api-version=$apiVersion"
    # Azure DevOps API doc: https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-requests/create?view=azure-devops-rest-7.0&tabs=HTTP
    # TFS API doc: https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-requests/create?view=vsts-rest-tfs-4.1&tabs=HTTP

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $header -Body $jsonBody -ContentType "application/json;charset=UTF-8"
        if ($Null -ne $response) {
            # If the response not null - the create PR succeeded
            $pullRequestId = $response.pullRequestId
            Write-Host "*************************"
            Write-Host "******** Success ********"
            Write-Host "*************************"
            Write-Host "Pull Request $pullRequestId created."
            if ($response.repository.webUrl){
                Write-Host "Web URL: $($response.repository.webUrl)/pullrequest/$pullRequestId"
            }
            
            
            if ($passPullRequestIdBackToADO) {
                $global:pullRequestIds += "$pullRequestId;"
            }

            $currentUserId = $response.createdBy.id

            # If set auto aomplete is true 
            if ($autoComplete) {
                SetAutoComplete -teamProject $teamProject -repositoryName $repositoryName -pullRequestId $pullRequestId -buildUserId $currentUserId -mergeStrategy $mergeStrategy -deleteSourch $deleteSourch -commitMessage $commitMessage -transitionWorkItems $transitionWorkItems
            }

            # If set bypass is true 
            if ($bypassPolicy) {
                $maxRetry = 2
                $retryCounter = 1
            
                BypassPR -teamProject $teamProject -repositoryName $repositoryName -pullRequestId $pullRequestId -buildUserId $currentUserId -mergeStrategy $mergeStrategy -deleteSourch $deleteSourch -commitMessage $commitMessage -transitionWorkItems $transitionWorkItems -bypassPolicy $bypassPolicy -bypassReason $bypassReason
                
                GetPRData -teamProject $teamProject -repositoryName $repositoryName -pullRequestId $pullRequestId | Out-Null
                while ($prData.status -ine "completed" -and $retryCounter -le $maxRetry) {
                    sleep 10
                    Write-Host "Retry Bypass: $retryCounter"
                    BypassPR -teamProject $teamProject -repositoryName $repositoryName -pullRequestId $pullRequestId -buildUserId $currentUserId -mergeStrategy $mergeStrategy -deleteSourch $deleteSourch -commitMessage $commitMessage -transitionWorkItems $transitionWorkItems -bypassPolicy $bypassPolicy -bypassReason $bypassReason
                    $retryCounter++
                } 
            }
        }
    }

    catch {
        # If the error contains TF401179 it's mean that there is alredy a PR for the branches, so I display a warning
        if ($_ -match "TF401179") {
            Write-Warning $_
        }

        else {
            # If there is an error - fail the task
            Write-Error $_
            Write-Error $_.Exception.Message
        }
    }
}

function CheckIfThereAreChanges {
    Param (
        [string]$sourceBranch,
        [string]$targetBranch, 
        [bool]$alwaysCreatePR
    )

    # Remove the refs/heads/ or merge/pull from branches name (see issue #85)
    if($sourceBranch.Contains("heads"))
    {
       $sourceBranch = $sourceBranch.Remove(0, 11)
    }
    elseif($sourceBranch.Contains("refs/pull"))
    {
       $sourceBranch = $sourceBranch.Remove(0, 10)
    }
    
    if($targetBranch.Contains("heads"))
    {
       $targetBranch = $targetBranch.Remove(0, 11)
    }
    elseif($sourceBranch.Contains("refs/pull"))
    {
       $targetBranch = $targetBranch.Remove(0, 10)
    }
    
    
    $head = @{ Authorization = "Bearer $global:token" }
    
    # Verify both source and target branches exist
    $url = "$env:System_TeamFoundationCollectionUri$($teamProject)/_apis/git/repositories/$($repositoryName)/refs?filter=heads"
    # API ref: https://learn.microsoft.com/en-us/rest/api/azure/devops/git/refs/list
    $refs = Invoke-RestMethod -Uri $url -Method Get -Headers $head -ContentType "application/json"
    $availableBranches = $refs.value.name
    Write-Debug "Available branches in repository '$($repositoryName)':`n$availableBranches"
    foreach ($branch in $sourceBranch,$targetBranch){
        if ($availableBranches -notcontains "refs/heads/$($branch)") {
            Write-Warning "Branch '$($branch)' not found in repository '$($repositoryName)'."
        }
    }
    
    $sourceBranch = [uri]::EscapeDataString($sourceBranch)
    $targetBranch = [uri]::EscapeDataString($targetBranch)
    $url = "$env:System_TeamFoundationCollectionUri$($teamProject)/_apis/git/repositories/$($repositoryName)/diffs/commits?baseVersion=$($targetBranch)&targetVersion=$($sourceBranch)&api-version=4.0&diffCommonCommit=true" + '&$top=2'
    $response = Invoke-RestMethod -Uri $url -Method Get -Headers $head -ContentType "application/json"
    if ($alwaysCreatePR -eq $true) {
        Write-Host "AlwaysCreatePr flag is true. Trying to perform a Pull Request..."

        if ($response.aheadCount -gt 0) {
            Write-Host "The source branch is ahead by $($response.aheadCount) commits. Perform a Pull Request..."
            return "true"
        } else {
            Write-Warning "***************************************************************"
            Write-Warning "There are no new commits in the source branch, no PR is needed!"
            Write-Warning "***************************************************************"
            return "false"
        }
    }
    else  {
        Write-Host "AlwaysCreatePr flag is false. A PR will only be created if there are actual file changes, but not if there is only a difference in commits."

        if ('' -eq $response.changeCounts) {
            Write-Warning "***************************************************************"
            Write-Warning "There are no file changes in the source branch, so no PR will be created!"
            if ($response.aheadCount -gt 0) {
                Write-Warning "The source branch is ahead by $($response.aheadCount) commits. If you want to create a PR in such a case, then please set the AlwaysCreatePr flag to true."
            }
            Write-Warning "***************************************************************"
            return "false"
        } else {
            Write-Host "$($response.aheadCount) new commits! File changes were found! Perform a Pull Request..."
            return "true"
        }
    }
}

function GetReviewerId() {
    [CmdletBinding()]
    Param
    (
        [string]$reviewers
    )

    $serverUrl = $env:System_TeamFoundationCollectionUri
    if ($serverUrl -imatch '^https?://(?<org>\w+)\.visualstudio\.com') {
        $serverUrl = "https://dev.azure.com/$($Matches.org)/"
    }
    Write-Host "Getting reviewer identities from TFS collection / Azure DevOps organization: $serverUrl"
    $head = @{ Authorization = "Bearer $global:token" }

    # If it's TFS/AzureDevOps Server
    if ($serverUrl -notmatch "visualstudio.com" -and $serverUrl -notmatch "dev.azure.com") {

        $url = "$($env:System_TeamFoundationCollectionUri)_apis/projects/$($env:System_TeamProject)/teams?api-version=4.0"

        $teams = Invoke-RestMethod -Method Get -Uri $url -Headers $head -ContentType 'application/json'
        Write-Debug $reviewers
        $split = $reviewers.Split(';').Trim()
        $reviewersId = @()
        ForEach ($reviewer in $split) {
            $isRequired = "false"
            if ($reviewer -match "req:") {
                $reviewer = $reviewer.Replace("req:","")
                $isRequired = "true"
            }
            # If the reviewer is user
            if ($reviewer.Contains("@") -or $reviewer.Contains("\")) {

                $teams.value.ForEach( {
                        $teamUrl = "$($env:System_TeamFoundationCollectionUri)_apis/projects/$($env:System_TeamProject)/teams/$($_.id)/members?api-version=4.1"
                        $team = Invoke-RestMethod -Method Get -Uri $teamUrl -Headers $head -ContentType 'application/json'
        
                        # If the team contains only 1 user
                        if ($team.count -eq 1) {
                            if ($team.value.identity.uniqueName -eq $reviewer) {
                                $userId = $team.value.identity.id
                                Write-Host $userId -ForegroundColor Green
                                $reviewersId += @{ 
                                    id = "$userId"
                                    isRequired = "$isRequired"
                                }
                                continue
                            }
                        }
                        else {
                            # If the team contains more than 1 user 
                            $userId = $team.value.identity.Where( { $_.uniqueName -eq $reviewer }).id
                            if ($null -ne $userId) {
                                Write-Host $userId -ForegroundColor Green
                                $reviewersId += @{ 
                                    id = "$userId"
                                    isRequired = "$isRequired"
                                }
                                continue
                            }
                        }
                    })
            }       

            # If the reviewer is team
            else {
                if ($teams.count -eq 1) {
                    if ($teams.value.name -eq $reviewer) {
                        $teamId = $teams.value.id
                        Write-Host $teamId -ForegroundColor Green
                        $reviewersId += @{ 
                            id = "$teamId"
                            isRequired = "$isRequired"
                        }
                    }
                }
                else {
                    $teamId = $teams.value.Where( { $_.name -eq $reviewer }).id
                    Write-Host $teamId -ForegroundColor Green
                    $reviewersId += @{ 
                        id = "$teamId"
                        isRequired = "$isRequired"
                    }
                }
            }
        }
    }
    
    # If it's Azure DevOps
    else {
        $urlBase = $serverUrl.Replace("dev.azure.com", "vssps.dev.azure.com") + "_apis/identities?api-version=7.0"
        # API reference: https://learn.microsoft.com/en-us/rest/api/azure/devops/ims/identities/read-identities?view=azure-devops-rest-7.0&tabs=HTTP
        Write-Debug $reviewers
        $reviewersId = @()
        foreach ($reviewer in $reviewers.Split(';').Trim()) {
            $isRequired = $reviewer -imatch "^req:"
            $reviewer = $reviewer -ireplace "^req:",""
            $searchFilter = if ($reviewer.Contains("@")) { "MailAddress" } else { "General" }
            $url = $urlBase, "searchFilter=$searchFilter", "filterValue=$reviewer" -join "&"
            Write-Debug "Looking for identity of reviewer: $reviewer at $url"
            $identities = Invoke-RestMethod -Uri $url -Method Get -ContentType application/json -Headers $head
            $idCount = $identities.count
            if ($idCount -lt 1) {
                Write-Warning "Could not find identity for reviewer: $reviewer, will skip."
            }
            if ($idCount -gt 1) {
                Write-Warning "Found $idCount identities matching reviewer: $reviewer, will include all of them."
            }
            foreach ($userId in $identities.value.id){
                Write-Debug "$reviewer $userId"
                $reviewersId += @{
                    id = $userId
                    isRequired = $isRequired
                }
            }
        }
    }
    return $reviewersId
}

function GetLinkedWorkItems {
    [CmdletBinding()]
    Param
    (
        [string]$sourceBranch,
        [string]$targetBranch,
        [string]$teamProject,
        [string]$repositoryName
    )
    $url = "$env:System_TeamFoundationCollectionUri$($teamProject)/_apis/git/repositories/$($repositoryName)/commitsBatch?api-version=4.0"
    $header = @{ Authorization = "Bearer $global:token" }
    $body = @{
        '$top'           = 101
        includeWorkItems = "true"
        itemVersion      = @{
            versionOptions = 0
            versionType    = 0
            version        = "$targetBranch"
        }
        compareVersion   = @{
            versionOptions = 0
            versionType    = 0
            version        = "$sourceBranch"
        }
    }
    $jsonBody = $body | ConvertTo-Json
    $response = Invoke-RestMethod -Method Post -Uri $url -Headers $header -Body $jsonBody -ContentType 'application/json'
    Write-Debug $response
    $commits = $response.value
    $commits.ForEach({ $_.workItems.ForEach({ Write-Debug $_ }) })
    $workItemsId = @()
    $commits.ForEach( { 
            if ($_.workItems.length -gt 0) {
                $_.workItems.ForEach({
                        Write-Debug $_
                        # Get the work item id from the work item url
                        $workItemsId += $_.url.split('/')[$_.url.split('/').count - 1]
                        $workItemsId.ForEach({ Write-Debug $_  })
                    })
            }
        })
    if ($workItemsId.Count -eq 1) {
        $workItems = @()
        $workItem = @{
            id  = $workItemsId[0]
            url = ""
        }
        $workItems += $workItem     
    }
    elseif ($workItemsId.Count -gt 0) {
        $workItems = @()
        ($workItemsId | Select-Object -Unique).ForEach( {
                $workItem = @{
                    id  = $_
                    url = ""
                }
                $workItems += $workItem
            })      
    }
    return $workItems
}

function SetAutoComplete {
    [CmdletBinding()]
    Param
    (
        [string]$pullRequestId,
        [string]$mergeStrategy,
        [bool]$deleteSourch,
        [string]$commitMessage,
        [bool]$transitionWorkItems,
        [string]$teamProject,
        [string]$repositoryName,
        [string]$buildUserId
    )

    $body = @{
        autoCompleteSetBy = @{ id = "$buildUserId" }
        completionOptions = ""
    }    

    $options = @{ 
        mergeStrategy       = "$mergeStrategy" 
        deleteSourceBranch  = "$deleteSourch"
        transitionWorkItems = "$transitionWorkItems"
        mergeCommitMessage  = "$commitMessage"
    }
    $body.completionOptions = $options

    $head = @{ Authorization = "Bearer $global:token" }
    $jsonBody = ConvertTo-Json $body
    Write-Debug $jsonBody
    $url = "$env:System_TeamFoundationCollectionUri$($teamProject)/_apis/git/repositories/$($repositoryName)/pullrequests/$($pullRequestId)?api-version=4.1"
    Write-Debug $url
    try {
        $response = Invoke-RestMethod -Uri $url -Method Patch -Headers $head -Body $jsonBody -ContentType application/json
        if ($Null -ne $response) {
            # If the response not null - the create PR succeeded
            Write-Host "Set Auto Complete to PR $pullRequestId."
        }
    }
    catch {
        Write-Warning "Can't set Auto Complete to PR $pullRequestId."
        Write-Warning $_
        Write-Warning $_.Exception.Message
    }
}

function BypassPR {
    [CmdletBinding()]
    Param
    (
        [string]$pullRequestId,
        [string]$mergeStrategy,
        [bool]$deleteSourch,
        [string]$commitMessage,
        [bool]$transitionWorkItems,
        [string]$teamProject,
        [string]$repositoryName,
        [string]$buildUserId,
        [bool]$bypassPolicy,
        [string]$bypassReason
    )

    $prData = GetPRData -teamProject $teamProject -repositoryName $repositoryName -pullRequestId $pullRequestId
    $lastCommitId = $prData.lastMergeSourceCommit.commitId
    $lastCommitUrl = $prData.lastMergeSourceCommit.url

    $body = @{
        completionOptions     = ""
        status                = "Completed"
        lastMergeSourceCommit = @{
            commitId = "$lastCommitId"
            url      = "$lastCommitUrl"
        }
    }    
    
    $options = @{ 
        mergeStrategy       = "$mergeStrategy" 
        deleteSourceBranch  = "$deleteSourch"
        transitionWorkItems = "$transitionWorkItems"
        mergeCommitMessage  = "$commitMessage"
        bypassPolicy        = "$bypassPolicy"
        bypassReason        = "$bypassReason"
    }
    $body.completionOptions = $options

    $head = @{ Authorization = "Bearer $global:token" }
    $jsonBody = ConvertTo-Json $body
    Write-Debug $jsonBody
    $url = "$env:System_TeamFoundationCollectionUri$($teamProject)/_apis/git/repositories/$($repositoryName)/pullrequests/$($pullRequestId)?api-version=4.1"
    Write-Debug $url
    try {
        $response = Invoke-RestMethod -Uri $url -Method Patch -Headers $head -Body $jsonBody -ContentType application/json
        if ($Null -ne $response) {
            Write-Host "Bypass PR $pullRequestId."
        }
    }
    catch {
        Write-Warning "Can't Bypass PR $pullRequestId."
        Write-Warning $_
        Write-Warning $_.Exception.Message
    }
}

function GetPRData {
    [CmdletBinding()]
    Param
    (
        [string]$pullRequestId,
        [string]$teamProject,
        [string]$repositoryName
    )

    $head = @{ Authorization = "Bearer $global:token" }
    $url = "$env:System_TeamFoundationCollectionUri$($teamProject)/_apis/git/repositories/$($repositoryName)/pullrequests/$($pullRequestId)?api-version=4.1"
    Write-Debug $url
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $head 
        if ($Null -ne $response) {
            $prData = $response
            Write-Host "Get Data PR $pullRequestId."
        }
    }
    catch {
        Write-Warning "Can't Get Data PR $pullRequestId."
        Write-Warning $_
        Write-Warning $_.Exception.Message
    }
    return $prData 
}

RunTask
