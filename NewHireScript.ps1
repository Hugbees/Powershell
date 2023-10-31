#This script will pull all information from a CSV generated in Bamboo HR and use it to create user accounts for new hires


#Set error preference, so script won't fill the screen with errors that aren't impactful. Important errors are captured and sent to slack
$ErrorActionPreference = 'silentlycontinue'

#Import AD module
Import-Module ActiveDirectory

#Set ErrorOccured variable to false. If error occured changs to true, the CSVs from BambooHR won't be deleted at the end of the script
$ErrorOccured = $false

#Set $runby variable to the first and last name of the person who ran the script, to be reported in the preamble
$RunBy = whoami
$Runby = $runBy.replace("ExampleDomain\","").replace("-adm","").replace("."," ")
$TextInfo = (Get-Culture).TextInfo
$runby = $TextInfo.ToTitleCase($runby)

#Pulls the SID of the account running the script, which is needed for the file path when running from an AWS AppStream box
$SID = Get-AdUser -Identity "$env:username"  | Select -ExpandProperty sid

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
        'Employment Status' = 'EmploymentStatus'
        }

#Imports CSV exported from BambooHR to $OriginalCSV, and sets formatted output to $NewCSV

$OriginalCSV = "C:\ExampleGoogleDrive\$sid\My Files\Google Drive\Shared Drives\Technology\NewHireScript\New_Hires_full_(Example_Company).csv"
$NewCSV = "C:\ExampleGoogleDrive\$sid\My Files\Google Drive\Shared Drives\Technology\NewHireScript\NewHiresFormatted.csv"

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
$NewUsers = Import-Csv "C:\ExampleGoogleDrive\$sid\My Files\Google Drive\Shared Drives\Technology\NewHireScript\NewHiresFormatted.csv"

# Starts a text log of the actions in the script. Appends existing log, if there is one
Start-Transcript -Path "C:\ExampleGoogleDrive\$sid\My Files\Google Drive\Shared Drives\Technology\NewHireScript\logs\NewUsers_$(get-date -f yyyy-MM-dd).log" -append -force


#Slack message preamble
    $SlackChannelUri =  "https://example.slackwebhook.com" 

    $Startmsg = @"
        {
        "pretext": ":camping: *New Employee account creation script* :camping:\nExecuted by RUNBY",
        "color": "#C0392B",
            }
"@
        $startbody = $startmsg.replace("RUNBY","$runby")
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $startbody -ContentType 'application/json'

#Assign variables to information from CSV

  Foreach ($User in $NewUsers) {
    $Firstname = $User.FirstName
    $AltName = $User.PreferredName
    $Department = $User.department
    $Division = $User.division    
    $Position = $User.Position
    $Location = $User.location
    $TempOU = "OU=TempNewUsers,OU=Users,OU=ExampleDomain,DC=ExampleDomain,DC=net"
    $Zip = $User.zipcode -replace " ",""
    $contractorOU = "OU=Contractors,OU=Users,OU=ExampleDomain,DC=ExampleDomain,DC=net"
    $UserOU = "OU=Employees,OU=Users,OU=ExampleDomain,DC=ExampleDomain,DC=net"
    $Lastname = $User.Lastname
    $Camp = $User.camp
    $EmployeeID = $User.employeeid
    $CostCenter = $User.costcenter
    $SalesSegment = $User.salessegment
    $Manager = $User.Manager
    $HomeEmail = $User.homeemail
    $EmpStatus = $user.employmentStatus
    $HireDate = $user.hiredate
    $Hiredate = [datetime]::ParseExact($hiredate, "dd MMM yyyy", $null).tostring('yyyy-MM-dd') 
    
#Check user manager against CSV of managers with usernames that don't follow firstname.lastname format
    $Mgr = Import-CSV "5\NewHireScript\CSVs\Managers.csv" | ForEach-Object {
    $MgrOld = $_.mgrold
    $MgrNew = $_.mgrnew
        if($Manager -match $MgrOld){
            $Manager = $MgrNew
        }
    }
#Remaining managers do match firstname.lastname, so this portion removes the space between first and lastnames and replaces it with a period
    $Manager = $Manager.replace(" ",".")

#Set ADP, Region, and country attributes based on location  
    if($location -match "New York"){
       $ADP = "aDPUS"
       $Region = "NA East"
       $countryCO = "United States"
       $countryC = "US"
       $countryCode = "840"           
     }
     if($location -match "San Francisco"){
       $ADP = "aDPUS"
       $Region = "NA West"
       $countryCO = "United States"
       $countryC = "US"
       $countryCode = "840" 
     }
     if($location -match "London"){
       $ADP = "aDPUK"  
       $Region = "EMEA"
       $countryCO = "United Kingdom"
       $countryC = "GB"
       $countryCode = "826"            
     }
     if($location -match "Melbourne"){
       $ADP = "aDPAU"
       $Region = "APAC"
       $countryCO = "Australia"
       $countryC = "AU"
       $countryCode = "036" 
     } 
     if($location -match "New Zealand"){
       $ADP = "aDPNZ"
       $Region = "APAC"
       $countryCO = "New Zealand"
       $countryC = "NZ"
       $countryCode = "554"              
     } 
     if($location -match "Chicago"){
       $ADP = "aDPUS"
       $Region = "NA East"
       $countryCO = "United States"
       $countryC = "US"
       $countryCode = "840"              
     }
#Berlin campers are not currently paid via ADP, so that variable is set to null.
     if($location -match "Berlin"){
       $ADP = $null
       $Region = "EMEA"
       $countryCO = "Germany"
       $countryC = "DE"
       $countryCode = "276" 
    }  
     
#Set $Role variable based on Cost Center to add to relevant role group later
if ($CostCenter -eq "Sales - AE"){
    $Role = "Role - Account Executive"
    }
if ($CostCenter -eq "Sales - AE Management"){
    $Role = "Role - Account Executive"
    }
if ($CostCenter -eq "Sales - AM"){
    $Role = "Role - Account Manager"
    }
if ($CostCenter -eq "Sales - AM Management"){
    $Role = "Role - Account Manager"
    }
if ($CostCenter -eq "Sales - Revenue Support"){
    $Role = "Role - Account Manager"
    }
if ($CostCenter -eq "Sales - SDR"){
    $Role = "Role - SDR"
    }
if ($CostCenter -eq "Sales - SDR Management"){
    $Role = "Role - SDR"
    }   
if ($CostCenter -eq "CS - Coach"){
    $Role = "Role - Customer Success"
    }
if ($CostCenter -eq "CS - Support"){
    $Role = "Role - Customer Success"
    }
if ($CostCenter -eq "CS - People Science"){
    $Role = "Role - People Science"
    }
if ($CostCenter -eq "Data"){
    $Role = "Role - Data Science"
    }
if ($CostCenter -eq "Engineering"){
    $Role = "Role - Engineer"
    }
if ($CostCenter -eq "Design"){
    $Role = "Role - Design"
    }
if ($CostCenter -eq "Finance"){
    $Role = "Role - Finance"
    }   
if ($CostCenter -eq "IT"){
    $Role = "Role - Technology"
    }
if ($CostCenter -eq "Legal"){
    $Role = "Role - Legal"
    }
if ($CostCenter -eq "People & Experience"){
    $Role = "Role - People Ops"
    }
if ($CostCenter -eq "Talent Acquisition"){
    $Role = "Role - Talent Acquisition"
    }
if ($CostCenter -eq "Product Management"){
    $Role = "Role - Product Management"
    }
if ($CostCenter -eq "Sales - AE"){
    $Role = "Role - Account Executive"
    }
if ($CostCenter -eq "Sales - AE Management"){
    $Role = "Role - Account Executive"
    }
if ($CostCenter -eq "Security"){
    $Role = "Role - Security"
    }
if ($CostCenter -eq "Brand"){
    $Role = "Role - Marketing"
    }
if ($CostCenter -eq "Field Marketing & Events"){
    $Role = "Role - Marketing"
    }
if ($CostCenter -eq "Lead Generation"){
    $Role = "Role - Marketing"
    }
if ($CostCenter -eq "Product Marketing"){
    $Role = "Role - Marketing"
    }
if ($CostCenter -eq "Customer Leads"){
    $Role = "Role - Customer Generic"
    }
if ($CostCenter -eq "GTM Ops"){
    $Role = "Role - Customer Generic"
    }
if ($CostCenter -eq "Org Admin"){
    $Role = "Role - Org Generic"
    }

#Set Employment Type variable
if ($EmpStatus -match "Part Time"){
    $EmpType = "Part Time"
    }
if ($EmpStatus -match "Full Time"){
    $EmpType = "Full Time"
    }
if ($EmpStatus -match "Contractor"){
    $EmpType = "Contractor"
    }    

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
    
<#Corrects Altfirst and Altlast for fringe case where user's preferred name 
contains a space, is not a full name, and matches their first name
#>
    if($altname -eq $Firstname){

        $Altfirst = $Firstname
        $Altlast = $Lastname
        }
    
#Check if user firstname and lastname would be greater than 20 characters.
#If so, sets $Sam variable as first initial and lastname. Uses preferred name if $altname is not empty
If ([string]::IsNullOrWhitespace($AltName)){
    $SamAcc = ("$Firstname"+"."+"$Lastname"  -replace " ","").ToLower()
    $SamAcc = $SamAcc.replace("'","")
    if ($SamAcc.length -gt 20){
        $Sam = ($Firstname.substring(0,1)+"."+$Lastname).ToLower()
        $Sam = $sam.replace(" ","")
    }
    else{
        $Sam = $SamAcc
    }
    }
    else{
    #same as above, but for preferred names
    $AltSamAcc = ("$AltFirst"+"."+"$Altlast" -replace " ","").ToLower()
    $AltSamAcc = $AltSamAcc.replace("'","")
    if ($AltSamAcc.length -gt 20){
        $Sam = ($Altfirst.substring(0,1)+"."+$Altlast).ToLower()
        $Sam = $sam.replace(" ","")
    }
    else{
        $Sam = $AltSamAcc
    }
}

#Set SAM, Name, Givenname, Surname and Email. Uses preferred name if $altname is not empty
If ([string]::IsNullOrWhitespace($AltName)){
    $Email = "$SamAcc@ExampleDomain.com"
    $Name = "$Firstname $Lastname"
    $Givenname = "$Firstname"
    $Surname = "$Lastname"
}
else{
    $Email = "$AltSamAcc@ExampleDomain.com"
    $Name = "$Altfirst $AltLast"
    $Givenname = "$AltFirst"
    $Surname = "$AltLast"
}

#Run function to remove special characters from SAMAccountName, UPN, and Emailaddress
$Sam = $Sam | Remove-StringLatinCharacters
$Email = $Email| Remove-StringLatinCharacters
<#
        Generate password as "CA-" + EmployeeID + lowercase First/AltFirst initial + lowercase Last/Altlast initial + Zip Code
        For user John Doe with Employee ID 1234, with zip code 10001, their password will be "CA-1234jd10001"
        The users employee ID is available to them on the "My Info" page of BambooHR
        #>

        $Password = ("CA" + "-" + $EmployeeID + $Firstname.substring(0,1).tolower() + $Lastname.substring(0,1).tolower() + $Zip)

    #Create the user account. Enclosed in a try/catch function to capture errors and send them to slack
    try{New-ADuser -Name "$Name"`
    -Displayname "$Name"`
    -SamAccountName "$Sam" `
    -Userprincipalname "$Sam@ExampleDomain.net"`
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
        }
     }catch{$Failure = "$Givenname $Surname"
            $ErrorOccured = $true
                $Failmsg = @"
                {
                "pretext": ":alert:*Account creation for FAILURE has encountered errors*:alert:",
                "text": "\nERROR",
                "color": "#C0392B",
                }
"@
                $failbody = $failmsg.replace("FAILURE","$failure").replace("ERROR", "$_")
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $Failbody -ContentType 'application/json'   
        }      
    #Add user to role group based on cost center
    Add-ADGroupMember -Identity "$Role" -Members $Sam
    #Add user to group named RG-CC-(CostCenter)
    $RGCC = $CostCenter.replace(" ","")
    Add-ADGroupMember -Identity "RG-CC-$RGCC" -Members $Sam
    #Add SDRs to Salesforce and Gong groups based on Cost Center and job title
        if ($CostCenter -match "Sales - SDR"){
            if ($CostCenter -match "Management"){
                Add-ADGroupMember -Identity "Application - Gong - Leadership" -Members $Sam
                Add-ADGroupMember -Identity "Application - Salesforce - Leadership" -Members $Sam
                }
             if($Position -match "Inbound"){
                Add-ADGroupMember -Identity "Application - Salesforce - SDR Inbound" -Members $Sam
                Add-ADGroupMember -Identity "Application - Gong - SDR Inbound" -Members $Sam
                }
            if($Position -match "Outbound"){
                Add-ADGroupMember -Identity "Application - Salesforce - SDR Outbound" -Members $Sam
                Add-ADGroupMember -Identity "Application - Gong - SDR Outbound" -Members $Sam
                }
            }
        #Check if user's personal email contains "everest.engineering", and add user to Contractors - Everest group if so
        if ($HomeEmail -match "everest.engineering"){
            Add-ADGroupMember -Identity "Contractors - Everest" -Members $Sam
            }
        #Add user to Camp group based on $camp
        if($camp -match "Career"){
            Add-ADGroupMember -Identity "Careers Camp" -Members $Sam
                }
        if($camp -match "Data Intelligence"){
            Add-ADGroupMember -Identity "Data Intelligence Camp" -Members $Sam
                }
        if($camp -match "Engagement"){
            Add-ADGroupMember -Identity "Engagement Camp" -Members $Sam
                }
        if($camp -match "Foundations"){
                Add-ADGroupMember -Identity "Foundations Camp" -Members $Sam
                }
        if($camp -match "Journeys"){
            Add-ADGroupMember -Identity "Journeys Camp" -Members $Sam
                }
        if($camp -match "Platform"){
            Add-ADGroupMember -Identity "Platform Camp" -Members $Sam
                }
        if($camp -match "Product Growth"){
            Add-ADGroupMember -Identity "Product Growth Camp" -Members $Sam
                }
}
            
#Pulls user info from $TempOU, sends notification to slack saying accounts have been successfully created

$Results = Get-ADUser -Filter * -SearchBase $TempOU -Property *
$msg = @"
    {
        "pretext": "*FULLNAME - EFFECTIVEDATE |* Account creation successful",
        "text": "Account Name: USERNAME\nTitle: JOBTITLE\nEmail: EMAILADDRESS\nManager: REPORTSTO\nOffice: PLACE",
        "color": "#82FB1B",
    }
"@
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
foreach ($user in $results){
    $FullName = $User.displayname
    $Username = $User.SamAccountName
    $Reports = Get-ADUser $User.Manager -Properties DisplayName
    $Reportsto = $Reports.displayname
    $JobTitle = $User.title
    $Place = $User.office
    $email = $user.emailaddress
    $effectiveDate = $user.effectiveDate
    $RGCC = $user.costcenter
    $EmployeeType = $user.employeeType
    $DN = $user.DistinguishedName
    $body = $msg.replace("FULLNAME","$Fullname").replace("USERNAME","$username").replace("REPORTSTO","$reportsto").replace("PLACE","$place").replace("EMAILADDRESS","$email").replace("JOBTITLE","$JobTitle").replace("EFFECTIVEDATE","$effectiveDate")
    Invoke-RestMethod -uri $SlackChannelUri -Method Post -body $body -ContentType 'application/json'


#Add each user to division group
    if($user.company -match "Customer"){
            Add-ADGroupMember -Identity "Customer Group" -Members $user.SamAccountName
            }
        elseif($user.company -match "Product"){
            Add-ADGroupMember -Identity "Product Group" -Members $user.SamAccountName
            }
        elseif($user.company -match "Org"){
           Add-ADGroupMember -Identity "Org Group" -Members $user.SamAccountName
            }

    if($place -match "New York"){
        Add-ADGroupMember -Identity "New York" -Members $username
        Add-ADGroupMember -Identity "Application - ADP" -Members $username
        }
    if($place -match "San Francisco"){
        Add-ADGroupMember -Identity "San Francisco" -Members $username
        Add-ADGroupMember -Identity "Application - ADP" -Members $username
        }
    if($place -match "Chicago"){
        Add-ADGroupMember -Identity "Chicago" -Members $username
        Add-ADGroupMember -Identity "Application - ADP" -Members $username
        }
    if($user.office -match "London"){
        Add-ADGroupMember -Identity "London" -Members $username
        Add-ADGroupMember -Identity "Application - ADP UK" -Members $username
        }
    if($place -match "Melbourne"){
        Add-ADGroupMember -Identity "Melbourne" -Members $username
        Add-ADGroupMember -Identity "Application - ADP AU" -Members $username
        }
    if($user.office -match "New Zealand"){
        Add-ADGroupMember -Identity "New Zealand" -Members $username
        Add-ADGroupMember -Identity "Application - ADP NZ" -Members $username
        }
    if($place -match "Berlin"){
        Add-ADGroupMember -Identity "Berlin" -Members $username
        }
    if($place -match "Remote"){
        Add-ADGroupMember -Identity "Remote" -Members $username
        }

    #Add user to Employee or Contractor group based on employeeType attribute
    if($user.EmployeeType -eq "Contractor"){
        Add-ADGroupMember -Identity "Contractors" -Members $Username
        Move-adobject -identity $DN -targetpath $contractorOU
        }
    if($user.EmployeeType -eq "Full Time"){
        Add-ADGroupMember -Identity "Employees" -Members $Username
        Move-adobject -identity $DN -targetpath $UserOU
        }
    if($user.EmployeeType -eq "Part Time"){
        Add-ADGroupMember -Identity "Employees" -Members $Username
        Move-adobject -identity $DN -targetpath $UserOU
        } 
        }



#Clean up CSVs that have been generated by the script, and delete the original BambooHR report

if ($ErrorOccured -ne $true){
    Remove-Item -Path "C:\ExampleGoogleDrive\$sid\My Files\Google Drive\Shared Drives\Technology\NewHireScript\New_Hires_full_(Example_Company).csv" -Force
    }
Remove-Item -Path "C:\ExampleGoogleDrive\$sid\My Files\Google Drive\Shared Drives\Technology\NewHireScript\NewHiresFormatted.csv" -Force
