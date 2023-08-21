#Pulls the SID of the account running the script, which is needed for the file path when running from an AWS AppStream box
$SID = Get-AdUser -Identity "$env:username"  | Select -ExpandProperty sid
$ErrorActionPreference = "SilentlyContinue"

#set text for prompt for user input
$title = ""
$message = "Do you want to get the membership of another group?"

#message shown when script is launched
Write-host -foregroundcolor Cyan "Group Membership List-O-Matic"

#set variables for yes/no prompt
$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
    "Prompts for another group"

$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
    "Exits the script"

$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

#create loop that restarts when 'yes' option is selected
:OuterLoop do
    {
    while($true){
#prompt for name of AD group of which you are fetching the membership
write-host -foregroundcolor Green 'Enter the name of the group that you would like to list the members of'
write-host -foregroundcolor gray 'Example: New York'
$adgroups = Read-Host -Prompt 'Group name'
#prompt for name of CSV membership is exported to
Write-host -ForegroundColor Green 'The results will be exported to a CSV file and uploaded to your Google Drive'
Write-host -ForegroundColor Green 'Please enter the desired file name' 
write-host -foregroundcolor gray "Example: New York Campers"
write-host -foregroundcolor gray "If you enter the name of an existing CSV (without the file extension), the results will be appended to that CSV"
$FileName = Read-Host -Prompt "File Name"
$GroupsCSV = "C:\ProgramData\UserDataFolders\$sid\My Files\Google Drive\My Drive\$FileName.csv"

#pull group members
foreach ($group in $adgroups){
     $users = Get-adgroupmember -identity $group | select -expandproperty samaccountname
     #get samaccoutnname for each user in the group
     ForEach ($user in $users){
        $sam = $user
        $name = Get-aduser -identity $user -properties * | select -ExpandProperty displayname
       #create custome object that simply lists the samaccountname and the group the user is a member of, then appends that to the CSV
       [pscustomobject]@{Name = $name; Username = $sam; GroupName = $group}|export-csv -path $groupscSV -append -NoTypeInformation
       }
        $result = $host.ui.PromptForChoice($title, $message, $options, 0)

        }
        
        
switch ($result)
    {
        1 {break OuterLoop}
                }
            }
    }
     until ($selection -eq $no)