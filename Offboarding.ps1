#Pulls the SID of the account running the script, which is needed for the file path when running from an AWS AppStream box
$SID = Get-AdUser -Identity "$env:username"  | Select -ExpandProperty sid
# Starts a text log of the actions in the script. Appends existing log, if there is one
Start-Transcript -Path "C:\ExampleGoogleDrive\$sid\My Files\Google Drive\Shared Drives\Technology\OffboardingTool\logs\Offboarding_$(get-date -f yyyy-MM-dd).log" -append -force
Import-module ActiveDirectory

$title = ""
$message = "Do you want to offboard another employee?"
Write-host -foregroundcolor Cyan "Employee Offboarding"

$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
    "Prompts for another user"

$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
    "Exits the script"

$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)


:OuterLoop do
    {
    while($true){
        function Get-RandomPassword {
                param (
                    [Parameter(Mandatory)]
                    [ValidateRange(4,[int]::MaxValue)]
                    [int] $length,
                    [int] $upper = 1,
                    [int] $lower = 1,
                    [int] $numeric = 1,
                    [int] $special = 1
                )
                if($upper + $lower + $numeric + $special -gt $length) {
                    throw "number of upper/lower/numeric/special char must be lower or equal to length"
                }
                $uCharSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                $lCharSet = "abcdefghijklmnopqrstuvwxyz"
                $nCharSet = "0123456789"
                $sCharSet = "/*-+,!?=()@;:._"
                $charSet = ""
                if($upper -gt 0) { $charSet += $uCharSet }
                if($lower -gt 0) { $charSet += $lCharSet }
                if($numeric -gt 0) { $charSet += $nCharSet }
                if($special -gt 0) { $charSet += $sCharSet }
                
                $charSet = $charSet.ToCharArray()
                $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
                $bytes = New-Object byte[]($length)
                $rng.GetBytes($bytes)
             
                $result = New-Object char[]($length)
                for ($i = 0 ; $i -lt $length ; $i++) {
                    $result[$i] = $charSet[$bytes[$i] % $charSet.Length]
                }
                $password = (-join $result)
                $valid = $true
                if($upper   -gt ($password.ToCharArray() | Where-Object {$_ -cin $uCharSet.ToCharArray() }).Count) { $valid = $false }
                if($lower   -gt ($password.ToCharArray() | Where-Object {$_ -cin $lCharSet.ToCharArray() }).Count) { $valid = $false }
                if($numeric -gt ($password.ToCharArray() | Where-Object {$_ -cin $nCharSet.ToCharArray() }).Count) { $valid = $false }
                if($special -gt ($password.ToCharArray() | Where-Object {$_ -cin $sCharSet.ToCharArray() }).Count) { $valid = $false }
             
                if(!$valid) {
                     $password = Get-RandomPassword $length $upper $lower $numeric $special
                }
                return $password
            }
        $password = Get-RandomPassword 12
        $Account = Read-Host -Prompt "Enter username of Camper to be offboarded"
        try{
        $DisabledUsers = "OU=Disabled Users,OU=Users,OU=ExampleDomain,DC=ExampleDomain,DC=net"
        $AccountDN = Get-ADUser -identity $Account -server "Mainframe-B01" | select $_.DistinguishedName
        Write-host -ForegroundColor gray "Disabling $Account..."
        if ($(get-aduser $accountDN).enabled -eq $true){
        Disable-ADAccount -Identity $AccountDN}
        else{write-host -foregroundcolor yellow "$Account is already disabled. Continuing..."}
        Write-host -ForegroundColor gray "Removing $AccountDN from all groups..."
        Get-AdPrincipalGroupMembership -Identity $AccountDN | Where-Object -Property Name -Ne -Value 'Domain Users' | Remove-AdGroupMember -Members $Account -Confirm:$False
        $CurrentGroup =  Get-AdPrincipalGroupMembership -Identity $AccountDN | select -expandproperty samaccountname
        Write-host -foregroundcolor DarkGray "$Account is now only a member of "-NoNewline; Write-Host -ForegroundColor Gray "$CurrentGroup"
        Write-host -ForegroundColor gray "Setting randomly generated password..."
        Set-ADAccountPassword -Identity  $accountDN -NewPassword (ConvertTo-SecureString -AsPlainText $Password -Force)
        Write-host -ForegroundColor gray "Moving $accountDN to $DisabledUsers..."
        Move-adobject -identity $AccountDN -targetpath $DisabledUsers
        Write-Host -ForegroundColor green "Success!"
   
    

    $result = $host.ui.PromptForChoice($title, $message, $options, 0)


switch ($result)
    {
        1 {break OuterLoop}
        }
    }
    catch{write-host -ForegroundColor red "`n$_"
        write-host -ForegroundColor red "`nAn Error occured. Please check the logs for more information."
        }
    }
}

until ($selection -eq $no)
 
