#Import AD module
Import-Module ActiveDirectory

#create lookup table to replace problematic values from BambooHR (Spaces, bad manager username, and Remote Location names) with values readable by powershell
$lookupTable = @{
        'Preferred Name'    = 'PreferredName'
        'Last Name'         = 'LastName'
        'Job Title'         = 'Position'
        'Reporting to'      = 'Manager'
        'First Name'        = 'Firstname'
        'Hire Date'         = 'HireDate'
        'Remote-Melb'       = 'Remote - Melbourne'
        'Remote-NYC'        = 'Remote - New York'
        'Remote-SF'         = 'Remote - San Francisco'
        'Remote-Berlin'     = 'Remote - Berlin'
        'Zip code'          = 'Zipcode'
        'Employee #'        = 'EmployeeID'
        'Cost Center'       = 'CostCenter'
        'Sales Segment'     = 'SalesSegment'
        'Home Email'        = 'HomeEmail'
        'Work Email'        = 'WorkEmail'
        'Employment Status' = 'EmploymentStatus'
        'Contract End Date' = 'ContractEndDate'
        }

#Pulls the SID of the account running the script, which is needed for the file path when running from an AWS AppStream box
$SID = Get-AdUser -Identity "$env:username"  | Select -ExpandProperty sid

#Date and time the script was run
$Date = Get-date

#set current state of $Nochanges to True
$Nochanges = $true

#Slack webhook for notifications
$SlackChannelUri =  "https://hooks.slack.com/services/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"
#Slack notification preamble
    $Startmsg = @"
        {
        "pretext": ":camping: *Account updates for DATE* :camping:",
        "color": "#C0392B",
            }
"@
        $startbody = $startmsg.replace("DATE","$Date")
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $startbody -ContentType 'application/json'

#Slack notification message template
$msg = @"
    {
        "pretext": "*Changes to account ADSAM*",
        "text": "CHANGES",
        "color": "#82FB1B",
    }
"@
$Emptymsg = @"
    {
        "text": "No changes made",
        "color": "#82FB1B",
    }
"@
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#Imports CSV exported from BambooHR to $OriginalCSV, and sets formatted output to $NewCSV

$OriginalCSV = "C:\ProgramData\UserDataFolders\$sid\My Files\Google Drive\Shared Drives\Team Technology\IT Operations\NewHireScript\AllEmployees_(Culture_Amp).csv"
$NewCSV = "C:\ProgramData\UserDataFolders\$sid\My Files\Google Drive\Shared Drives\Team Technology\IT Operations\NewHireScript\AllEmployeesFormatted.csv"

#Runs data in $OriginalCSV and replaces problematic entries, then outputs to $NewCSV file location

Get-Content -Path $OriginalCSV | ForEach-Object {
    $line = $_

    $lookupTable.GetEnumerator() | ForEach-Object {
        if ($line -match $_.Key)
        {
            $line = $line -replace $_.Key, $_.Value
        }
    }
   $line
} | Set-Content -Path $NewCSV

#Set a new function to remove all diacritics from campers name
function Remove-StringLatinCharacters
{
    PARAM (
        [parameter(ValueFromPipeline = $true)]
        [string]$String
    )
    PROCESS
    {
        [Text.Encoding]::ASCII.GetString([Text.Encoding]::GetEncoding("Cyrillic").GetBytes($String))
    }
}

<#Run the function against formatted CSV to remove diacritics in ALL fields 
    $NewContent = Get-content $NewCSV | Remove-StringLatinCharacters
    
    # Overwrite the current file with the new content
    $NewContent | Set-Content $NewCSV
    #>

#Imports our freshly created properly formatted CSV
$AllEmployees = Import-Csv "C:\ProgramData\UserDataFolders\$sid\My Files\Google Drive\Shared Drives\Team Technology\IT Operations\NewHireScript\AllEmployeesFormatted.csv"

  Foreach ($User in $AllEmployees){
    $Firstname = $User.FirstName
    $AltName = $User.PreferredName
    $Department = $User.department
    $Division = $User.division    
    $Position = $User.Position
    $Location = $User.location
    $TempOU = "OU=TempNewUsers,OU=Users,OU=cultureamp,DC=cultureamp,DC=net"
    $Zip = $User.zipcode -replace " ",""
    $contractorOU = "OU=Contractors,OU=Users,OU=cultureamp,DC=cultureamp,DC=net"
    $UserOU = "OU=Employees,OU=Users,OU=cultureamp,DC=cultureamp,DC=net"
    $Lastname = $User.Lastname
    $Camp = $User.camp
    $EmployeeID = $User.employeeid
    $CostCenter = $User.costcenter
    $SalesSegment = $User.salessegment
    $Manager = $User.Manager
    $WorkEmail = $User.workemail
    $EmpStatus = $user.employmentStatus
    $RGCC = $CostCenter.replace(" ","")
    $ContractEndDate = $user.ContractEndDate
    $ContractEndDate = [datetime]::ParseExact($ContractEndDate, "dd MMM yyyy", $null).tostring('d')
    $AccountExpire = ([datetime]"$ContractEndDate").AddDays(2)
    $HireDate = $user.hiredate
    $Hiredate = [datetime]::ParseExact($hiredate, "dd MMM yyyy", $null).tostring('yyyy-MM-dd')
    #Check user manager against CSV of managers with usernames that don't follow firstname.lastname format
    $Mgr = Import-CSV "C:\ProgramData\UserDataFolders\$sid\My Files\Google Drive\Shared Drives\Team Technology\IT Operations\NewHireScript\CSVs\Managers.csv" | ForEach-Object {
    $MgrOld = $_.mgrold
    $MgrNew = $_.mgrnew
        if($Manager -match $MgrOld){
            $Manager = $MgrNew
        }
    }
#Remaining managers do match firstname.lastname, so this portion removes the space between first and lastnames and replaces it with a period
    $Manager = $Manager.replace(" ",".")
 
    <#Check to see if preferred name contains a space, indicating it's a full name. 
    If so, sets anything before the last instance of a space as $Altfirst and after last space as $Lastname
    Will not recognize information properly if last name has a space, but that's pretty uncommon
    #>

    if ($altname -match " "){
        $AltLast = $altname.split(" ")[-1]
        $AltFirst = $altname.Substring(0, $altname.lastIndexOf(' '))
        }
    else{
        $AltLast = $Lastname
        $Altfirst = $Altname
        }
      If ([string]::IsNullOrWhitespace($Altname)){
            $Name = "$Firstname $Lastname"
            $Givenname = "$Firstname"
            $Surname = "$Lastname"
        }
        else{
            $Name = "$Altfirst $AltLast"
            $Givenname = "$AltFirst"
            $Surname = "$AltLast"
        }
        
    #Set ADP, Region, and country attributes based on location  
    if($location -match "New York"){
       $ADP = "aDPUS"
       $Region = "NA East"
       $countryCO = "United States"
       $countryC = "US"
       $countryCode = "840"
       $OfficeGroup = "New York"
       $ADPGroup = "Application - ADP"           
     }
     if($location -match "San Francisco"){
       $ADP = "aDPUS"
       $Region = "NA West"
       $countryCO = "United States"
       $countryC = "US"
       $countryCode = "840" 
       $OfficeGroup = "San Francisco"
       $ADPGroup = "Application - ADP"
     }
     if($location -match "London"){
       $ADP = "aDPUK"  
       $Region = "EMEA"
       $countryCO = "United Kingdom"
       $countryC = "GB"
       $countryCode = "826" 
       $OfficeGroup = "London"
       $ADPGroup = "Application - ADP UK"           
     }
     if($location -match "Melbourne"){
       $ADP = "aDPAU"
       $Region = "APAC"
       $countryCO = "Australia"
       $countryC = "AU"
       $countryCode = "036" 
       $OfficeGroup = "Melbourne"
       $ADADPGroup = "Application - ADP AU"
     } 
     if($location -match "New Zealand"){
       $ADP = "aDPNZ"
       $Region = "APAC"
       $countryCO = "New Zealand"
       $countryC = "NZ"
       $countryCode = "554"       
       $OfficeGroup = "New Zealand" 
       $ADADPGroup = "Application - ADP NZ"      
     } 
     if($location -match "Chicago"){
       $ADP = "aDPUS"
       $Region = "NA East"
       $countryCO = "United States"
       $countryC = "US"
       $countryCode = "840"        
       $OfficeGroup = "Chicago"
       $ADADPGroup = "Application - ADP"      
     }
#Berlin campers are not currently paid via ADP, so that variable is set to null.
     if($location -match "Berlin"){
       $ADP = $null
       $Region = "EMEA"
       $countryCO = "Germany"
       $countryC = "DE"
       $countryCode = "276" 
       $OfficeGroup = "Berlin"
    }
#Clear slack message variables
$Changes,$slackmessage = $null
#clear $ADuser variable before pulling next user
$ADuser = $null
#Clear AD variables from previous users
$ADDisplayName,$ADSurname,$adgivenname,$ADSam,$Reports,$admanager,$ADTitle,$ADLocation,$ADemail,$ADCostCenter,$ADDN,$ADSalesSegment,$ADEmpStatus,$ADDepartment,$ADDivision,$ADRegion,$ADc,$ADcountryCO,$ADCountryCode,$ADExpire,$ADRGCC = $null
#Find AD user account based on Work Email in BambooHR
    $ErrorOccured = $false
    $ADUser = Get-ADUser -Filter  {emailaddress -like $workemail} -Properties *
    if([string]::IsNullOrWhitespace($ADUser)){
    $Failure = "$workemail"
            $ErrorOccured = $true
                $Failmsg = @"
                {
                "pretext": ":alert:*No account found with email FAILURE*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $failbody = $failmsg.replace("FAILURE","$failure").replace("ERROR", "$_")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $Failbody -ContentType 'application/json'
                }
#Set variables for all attributes that are currently in AD
    $ADDisplayName = $ADUser.displayname
    $ADSurname = $aduser.surname
    $adgivenname = $aduser.givenname
    $ADSam = $aduser.samaccountname
    $Reports = $aduser.manager
    $admanager = Get-ADuser -identity $reports -Properties samaccountname | select -ExpandProperty samaccountname
    $ADTitle = $ADUser.title
    $ADLocation = $ADUser.physicalDeliveryOfficeName
    $ADemail = $ADuser.emailaddress
    $ADCostCenter= $ADuser.costcenter
    $ADDN = $ADuser.DistinguishedName
    $ADSalesSegment = $ADUser.salessegment
    $ADEmpStatus = $ADuser.employeeType
    $ADDepartment = $ADUser.department
    $ADDivision = $ADuser.company
    $ADRegion = $ADuser.region
    $ADc = $aduser.c
    $ADcountryCO = $aduser.co
    $ADCountryCode = $aduser.countryCode
    $ADExpire = $aduser.accountexpirationdate
    $ADRGCC = $ADCostCenter.replace(" ","")

#Set office group variable based on AD Location. Variable will be used for removing user from old office group if they have changed locations
    if($ADlocation -match "New York"){
        $ADOfficeGroup = "New York"
        $ADADP = "adpUS"
        $ADADPGroup = "Application - ADP"
        }
    if($ADlocation -match "San Francisco"){
        $ADOfficeGroup = "San Francisco"
        $ADADP = "adpUS"
        $ADADPGroup = "Application - ADP"
        }
    if($ADlocation -match "Chicago"){
        $ADOfficeGroup = "Chicago"
        $ADADP = "adpUS"
        $ADADPGroup = "Application - ADP"
        }
    if($ADlocation -match "London"){
        $ADOfficeGroup = "London"
        $ADADP = "adpUS"
        $ADADPGroup = "Application - ADP UK"
        }
    if($ADlocation -match "Berlin"){
        $ADOfficeGroup = "Berlin"
        $ADADP = $null
        }
    if($ADlocation -match "Melbourne"){
        $ADOfficeGroup = "Melbourne"
        $ADPADP = "adpAU"
        $ADADPGroup = "Application - ADP AU"
        }
    if($ADlocation -match "New Zealand"){
        $ADOfficeGroup = "New Zealand"
        $ADADP = "adpNZ"
        $ADADPGroup = "Application - ADP NZ"
        }
    $ADPID = $ADuser.$adadp
if($ErrorOccured -eq $false){
#Update manager if different in BambooHR
    try{
        if ($ADManager -ne $Manager){
        Set-ADUser -Identity $ADSam -manager $Manager
        $Changes = "Manager updated to $Manager from $AdManager"
        }
        }catch{$ChangeErrorMsg = @"
                {
                "pretext": ":alert:*Error updating manager for ADSAM*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $errorbody = $changeerrormsg.replace("FAILURE","$failure").replace("ERROR", "$_").replace("ADSAM","$ADsam")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $errorbody -ContentType 'application/json'        
        }
#Update title if different in BambooHR
    try{
        if ($ADTitle -ne $Position){
        Set-ADUser -Identity $ADSam -Replace @{title = "$Position"}
        $Changes = "$Changes" + "\nTitle updated to $Position from $ADTitle"
        }
        }catch{$ChangeErrorMsg = @"
                {
                "pretext": ":alert:*Error updating title for ADSAM*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $errorbody = $changeerrormsg.replace("FAILURE","$failure").replace("ERROR", "$_").replace("ADSAM","$ADsam")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $errorbody -ContentType 'application/json'
        }    
#Checks if BambooHR location does NOT contain remote, and AD location DOES contain remote. If so, removes user from Remote group in AD
    try{
        if ($location -notlike "Remote*"){
        if($ADLoation -like "Remote*"){
            Remove-ADGroupMember -Identity "Remote" -Members $ADSam
            }
        }
    }catch{$ChangeErrorMsg = @"
                {
                "pretext": ":alert:*Error removing ADSAM from Remote group*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $errorbody = $changeerrormsg.replace("FAILURE","$failure").replace("ERROR", "$_").replace("ADSAM","$ADsam")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $errorbody -ContentType 'application/json'
        }
#Update location if different in BambooHR. Remove user from old office group and add to new. Update ADP attribute to populate the correct field
    try{
        if ($ADLocation -ne $Location){
        Set-ADUser -Identity $ADSam -Replace @{physicalDeliveryOfficeName = "$Location"}
        if ($ADOfficeGroup -ne $null){
            Remove-ADGroupMember -Identity $ADOfficeGroup -Members $ADSam -Confirm:$false
                }
        Add-ADGroupMember -Identity $OfficeGroup -Members $ADSam
        if($location -like "Berlin"){
            Set-ADuser -Identity $ADSam -clear $ADADP
            if ($ADADPGroup -ne $null){
            Remove-ADGroupMember -Identity $ADADPGroup -Members $ADSam -Confirm:$false
                }
        }elseif ($ADLocation -ne "Berlin"){
            Set-ADUser -Identity $ADSam -Replace @{$ADP = "$ADPID"}
            Set-ADuser -Identity $ADSam -clear $ADADP
            if($ADADPGroup -ne $ADPGroup){
                if ($ADADPGroup -ne $null){
                    Remove-ADGroupMember -Identity $ADADPGroup -Members $ADSam -Confirm:$false
                        }
            Add-ADGroupMember -Identity $ADPGroup -Members $ADSam
                }
        }elseif ($ADLocation -like "Berlin"){
            Set-ADUSer -Identity $ADSam -Replace @{$ADP = $aDP = $EmployeeID.padleft(6, '0')}
            Add-ADGroupMember -Identity $ADPGroup -Members $ADSam
            }
        $Changes = "$Changes" + "\nLocation updated to $Location from $ADLocation"
        }
    }catch{$ChangeErrorMsg = @"
                {
                "pretext": ":alert:*Error updating Location for ADSAM*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $errorbody = $changeerrormsg.replace("FAILURE","$failure").replace("ERROR", "$_").replace("ADSAM","$ADsam")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $errorbody -ContentType 'application/json'
        }

#Update department if different in BambooHR
    try{
        if ($ADDepartment -ne $department){
        Set-ADUser -Identity $ADSam -Replace @{Department = "$department"}
        $Changes = "$Changes" + "\nDepartment updated to $Department from $ADDepartment"
        }
    }catch{$ChangeErrorMsg = @"
                {
                "pretext": ":alert:*Error updating Department for ADSAM*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $errorbody = $changeerrormsg.replace("FAILURE","$failure").replace("ERROR", "$_").replace("ADSAM","$ADsam")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $errorbody -ContentType 'application/json'
        }
#Update division if different in BambooHR. Remove from old division group and add to new
    try{
        if ($ADDivision-ne $Division){
        Set-ADUser -Identity $ADSam -Replace @{company = "$Division"}
            if ($ADDivision -ne $null){
            Remove-ADGroupMember -Identity "$ADDivision Group" -Members $ADSam -Confirm:$false
                }
        Add-ADGroupMember -Identity "$Division Group" -Members $ADSam
        $Changes = "$Changes" + "\nDivision updated to $Division from $ADDivision"
        }
    }catch{$ChangeErrorMsg = @"
                {
                "pretext": ":alert:*Error updating Division for ADSAM*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $errorbody = $changeerrormsg.replace("FAILURE","$failure").replace("ERROR", "$_").replace("ADSAM","$ADsam")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $errorbody -ContentType 'application/json'
        }
#If region is different in BambooHR, update region, country, country code, and C    
    try{
        if ($ADRegion -ne $Region){
        Set-ADUser -Identity $ADSam -Replace @{region = "$region"; c = "$countryC"; CO = "$countryCO"; countryCode = "$countryCode"}
        $Changes = "$Changes" + "\nRegion updated to $Region from $ADregion"
        }
    }catch{$ChangeErrorMsg = @"
                {
                "pretext": ":alert:*Error updating Region for ADSAM*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $errorbody = $changeerrormsg.replace("FAILURE","$failure").replace("ERROR", "$_").replace("ADSAM","$ADsam")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $errorbody -ContentType 'application/json'
        }
#Update Cost Center if different in BambooHR. Remove user from old cost center role group and add to new
    try{
        if ($ADCostCenter -ne $CostCenter){
        Set-ADUser -Identity $ADSam -Replace @{costCenter = "$costCenter"}
            if ($ADRGCC -ne $null){
                Remove-ADGroupMember -Identity "RG-CC-$ADRGCC" -Members $ADSam -Confirm:$false
                    }
        Add-ADGroupMember -Identity "RG-CC-$RGCC" -Members $ADSam
        $Changes = "$Changes" + "\nCost center updated to $CostCenter from $ADCostCenter"
        }
    }catch{$ChangeErrorMsg = @"
                {
                "pretext": ":alert:*Error updating Cost Center for ADSAM*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $errorbody = $changeerrormsg.replace("FAILURE","$failure").replace("ERROR", "$_").replace("ADSAM","$ADsam")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $errorbody -ContentType 'application/json'
        }
#Checks for users who have matching cost centers in AD and Bamboo, but are not in an RG-CC group
    try{
        $NoRoleGroup = Get-ADPrincipalGroupMembership -identity $adsam |where samaccountname -like "RG-CC*" | select -expandproperty samaccountname
        if ($NoRoleGroup -notlike "RG-CC*"){
            Add-ADGroupMember -Identity "RG-CC-$RGCC" -Members $ADSam
            $Changes = "$Changes" + "\nUpdated role group to RG-CC-$RGCC"
            }
        }catch{$ChangeErrorMsg = @"
                {
                "pretext": ":alert:*Error updating Role Group for ADSAM*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $errorbody = $changeerrormsg.replace("FAILURE","$failure").replace("ERROR", "$_").replace("ADSAM","$ADsam")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $errorbody -ContentType 'application/json'
        }
#Update Sales Segment if different in BambooHR
    try{
        if ($ADSalesSegment-notlike $SalesSegment){
        Set-ADUser -Identity $ADSam -Replace @{SalesSegment = "$SalesSegment"}
        $Changes = "$Changes" + "\nSales segment updated to $SalesSegment from $ADsalessegment"
        }
    }catch{$ChangeErrorMsg = @"
                {
                "pretext": ":alert:*Error updating Sales Segment for ADSAM*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $errorbody = $changeerrormsg.replace("FAILURE","$failure").replace("ERROR", "$_").replace("ADSAM","$ADsam")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $errorbody -ContentType 'application/json'
        }
#Update Employment status if different in BambooHR
    try{
        if ($ADEmpStatus -ne $EmpStatus){
        Set-ADUser -Identity $ADSam -Replace @{employeeType = "$EmpStatus"}
        $Changes = "$Changes" + "\nEmployee type updated to $EmpStatus from $ADEmpStatus"
        }
    }catch{$ChangeErrorMsg = @"
                {
                "pretext": ":alert:*Error updating Employee Type for ADSAM*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $errorbody = $changeerrormsg.replace("FAILURE","$failure").replace("ERROR", "$_").replace("ADSAM","$ADsam")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $errorbody -ContentType 'application/json'
        }
#Update Account expiration to Contract End Date from BambooHR +36 hours. If contract end date is blank and the AD account has an expiration date, sets account expiration to never
    try{
        If ([string]::IsNullOrWhitespace($ContractEndDate)){
        if (-not([string]::IsNullOrWhitespace($ContractEndDate))){
            Clear-ADAccountExpiration -Identity $ADSam
            $Changes = "$Changes" + "\nAccount expiration date removed"
            }
        }elseif($ADExpire -notcontains $AccountExpire){
            Set-ADAccountExpiration -Identity $adsam -DateTime $AccountExpire
            $Changes = "$Changes" + "\nAccount expiration date set to $AccountExpire"
        }
    }catch{$ChangeErrorMsg = @"
                {
                "pretext": ":alert:*Error updating Account Expiration for ADSAM*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $errorbody = $changeerrormsg.replace("FAILURE","$failure").replace("ERROR", "$_").replace("ADSAM","$ADsam")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $errorbody -ContentType 'application/json'
        }
#Add user to Employee or Contractor group based on employeeType attribute
    try{
        if($EmpStatus -eq "Contractor"){
        $EmployeesMembers = Get-ADPrincipalGroupMembership -identity $adsam |where samaccountname -eq "Employees" | select -expandproperty samaccountname
        $ContractorsMembers = Get-ADPrincipalGroupMembership -identity $adsam | where samaccountname -eq "Contractors" | select -expandproperty samaccountname
        if ($ContractorsMembers -ne "contractors"){
        Add-ADGroupMember -Identity "Contractors" -Members $ADSam
        $Changes = "$Changes" + "\nAdded to contractors group"
                }
        if ($EmployeesMembers -eq "Employees"){
            Remove-ADGroupMember -Identity "Employees" -Members $ADSam -Confirm:$false
            }
                }
    if($EmpStatus -eq "Contractor"){
        if ($ADDN -notlike "*OU=Contractors*"){
        Move-adobject -identity $ADDN -targetpath $contractorOU
        $ADDN = get-aduser $adsam -Properties distinguishedname | select -ExpandProperty distinguishedname
        $Changes = "$Changes" + "\nMoved to Contractors OU"
                }
            }
    if($EmpStatus -eq "Full Time"){
        $EmployeesMembers = Get-ADPrincipalGroupMembership -identity $adsam |where samaccountname -eq "Employees" | select -expandproperty samaccountname
        $ContractorsMembers = Get-ADPrincipalGroupMembership -identity $adsam | where samaccountname -eq "Contractors" | select -expandproperty samaccountname
        if ($EmployeesMembers -ne "Employees"){
        Add-ADGroupMember -Identity "Employees" -Members $ADSam
        $Changes = "$Changes" + "\nAdded to Employees group"
                }
        if($ContractorsMembers -eq "contractors"){
            Remove-ADGroupMember -Identity "Contractors" -Members $ADSam -Confirm:$false
            }
        if ($ADDN -notlike "*OU=Employees*"){
        Move-adobject -identity $ADDN -targetpath $userOU
        $ADDN = get-aduser $adsam -Properties distinguishedname | select -ExpandProperty distinguishedname
        $Changes = "$Changes" + "\nMoved to Employees OU"
                }
            }
    if($EmpStatus -eq "Part Time"){
        $EmployeesMembers = Get-ADGroupMember -Identity "Employees" | where samaccountname -eq $ADSam | select -expandproperty samaccountname
        $ContractorsMembers = Get-ADPrincipalGroupMembership -identity $adsam | where samaccountname -eq "Contractors" | select -expandproperty samaccountname
        if ($EmployeesMembers -ne $ADSam){
        Add-ADGroupMember -Identity "Employees" -Members $ADSam
        $Changes = "$Changes" + "\nAdded to Employees group"
                }
        if($ContractorsMembers -eq "contractors"){
            Remove-ADGroupMember -Identity "Contractors" -Members $ADSam -Confirm:$false
            }
        if ($ADDN -notlike "*OU=Employees*"){
        Move-adobject -identity $ADDN -targetpath $userOU
        $ADDN = get-aduser $adsam -Properties distinguishedname | select -ExpandProperty distinguishedname
        $Changes = "$Changes" + "\nMoved to Employees OU"
                }
            }
        }catch{$ChangeErrorMsg = @"
                {
                "pretext": ":alert:*Error updating Employee Type Group/OU for ADSAM*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $errorbody = $changeerrormsg.replace("FAILURE","$failure").replace("ERROR", "$_").replace("ADSAM","$ADsam")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $errorbody -ContentType 'application/json'
        }
#If name has changed, update Display name, Given Name, and Object name
try{
    if ("$ADGivenname$ADSurname" -ne "$Givenname$Surname"){
         Set-ADUser -Identity $ADsam -Replace @{GivenName = "$GivenName"}
         Set-ADUser -Identity $ADsam -Replace @{SN = "$Surname"}
         Set-AdUser -Identity $ADDN -DisplayName "$Givenname $Surname"
         Rename-ADObject -Identity $ADDN -newname "$Givenname $Surname" -PassThru
     $Changes = "$Changes" + "\nName updated to $Givenname $Surname from $ADGivenname $ADSurname"
    }
}catch{$ChangeErrorMsg = @"
                {
                "pretext": ":alert:*Error updating Name for ADSAM*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $errorbody = $changeerrormsg.replace("FAILURE","$failure").replace("ERROR", "$_").replace("ADSAM","$ADsam")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $errorbody -ContentType 'application/json'
        }
#Send Slack notification with changes made for each user
if(-not([string]::IsNullOrWhitespace($changes))){
    $Slackmessage = $msg.replace("CHANGES","$Changes").replace("ADSAM","$ADsam")
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $slackmessage -ContentType 'application/json'
    $Nochanges = $false
    }
}
}
if ($Nochanges -eq $true){
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $emptymsg -ContentType 'application/json'
}



    


<#Template
    if ($ADXXX -ne $YYY){
        Set-ADUser -Identity $ADSam -Replace @{XXX = "$YYY"}
        }
    #>

<# try{New-ADuser -Name "$Name"`
    -Displayname "$Name"`
    -SamAccountName "$Sam" `
    -Userprincipalname "$Sam@cultureamp.net"`
    -GivenName "$Givenname" `
    -emailaddress "$Email"`
    -Surname "$surname" `
    -path $TempOU `
    -AccountPassword (ConvertTo-SecureString $password -AsPlainText -force) -passThru -ChangePasswordAtLogon $true -Enabled $true `
    -Department "$Department" `
    -Company "$Division" `
    -title "$Position" `
    -office "$location" `
    -manager "$manager" `
    -OtherAttributes @{costCenter = "$CostCenter"; region = "$region"; effectiveDate = "$hiredate"; c = "$countryC"; CO = "$countryCO"; countryCode = "$countryCode";employeeType = "$EmpType"}`
    #Check to see if $ADP or $SalesSegment variables have a value. If so, sets those variables               
    if(-not([string]::IsNullOrWhitespace($ADP))){
    Set-AdUSer -Identity "$Sam" -replace @{$aDP = $EmployeeID.padleft(6, '0')}
        }
    if(-not([string]::IsNullOrWhitespace($salesSegment))){
    Set-ADUser -Identity "$Sam" -replace @{ salesSegment = "$salesSegment"}
#>