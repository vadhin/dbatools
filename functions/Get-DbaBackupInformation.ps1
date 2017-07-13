function Get-DbaBackupInformation {
    <#
    .SYNOPSIS
        Restores a SQL Server Database from a set of backupfiles
    
    .DESCRIPTION
        Upon bein passed a list of potential backups files this command will scan the files, select those that contain SQL Server
        backup sets. It will then filter those files down to a set 

        The function defaults to working on a remote instance. This means that all paths passed in must be relative to the remote instance.
        XpDirTree will be used to perform the file scans
                
        Various means can be used to pass in a list of files to be considered. The default is to non recursively scan the folder
        passed in.
    
    .PARAMETER Path
        Path to SQL Server backup files.
        
        Paths passed in as strings will be scanned using the desired method, default is a non recursive folder scan
        Accepts multiple paths seperated by ','
        
        Or it can consist of FileInfo objects, such as the output of Get-ChildItem or Get-Item. This allows you to work with
        your own filestructures as needed
    
    .PARAMETER SqlInstance
        The SQL Server instance to restore to.
    
    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.
    
    .PARAMETER DatabaseName
        Name to restore the database under.
        Only works with a single database restore. If multiple database are found in the provided paths then we will exit
    
    .PARAMETER DestinationDataDirectory
        Path to restore the SQL Server backups to on the target instance.
        If only this parameter is specified, then all database files (data and log) will be restored to this location
    
    .PARAMETER DestinationLogDirectory
        Path to restore the database log files to.
        This parameter can only be specified alongside DestinationDataDirectory.
    
    .PARAMETER RestoreTime
        Specify a DateTime object to which you want the database restored to. Default is to the latest point  available in the specified backups
    
    .PARAMETER NoRecovery
        Indicates if the databases should be recovered after last restore. Default is to recover
    
    .PARAMETER WithReplace
        Switch indicated is the restore is allowed to replace an existing database.
    
    .PARAMETER XpDirTree
        Switch that indicated file scanning should be performed by the SQL Server instance using xp_dirtree
        This will scan recursively from the passed in path
        You must have sysadmin role membership on the instance for this to work.
    
    .PARAMETER OutputScriptOnly
        Switch indicates that ONLY T-SQL scripts should be generated, no restore takes place
    
    .PARAMETER VerifyOnly
        Switch indicate that restore should be verified
    
    .PARAMETER MaintenanceSolutionBackup
        Switch to indicate the backup files are in a folder structure as created by Ola Hallengreen's maintenance scripts.
        This swith enables a faster check for suitable backups. Other options require all files to be read first to ensure we have an anchoring full backup. Because we can rely on specific locations for backups performed with OlaHallengren's backup solution, we can rely on file locations.
    
    .PARAMETER FileMapping
        A hashtable that can be used to move specific files to a location.
        $FileMapping = @{'DataFile1'='c:\restoredfiles\Datafile1.mdf';'DataFile3'='d:\DataFile3.mdf'}
        And files not specified in the mapping will be restored to their original location
        This Parameter is exclusive with DestinationDataDirectory
    
    .PARAMETER IgnoreLogBackup
        This switch tells the function to ignore transaction log backups. The process will restore to the latest full or differential backup point only
    
    .PARAMETER useDestinationDefaultDirectories
        Switch that tells the restore to use the default Data and Log locations on the target server. If they don't exist, the function will try to create them
    
    .PARAMETER ReuseSourceFolderStructure
        By default, databases will be migrated to the destination Sql Server's default data and log directories. You can override this by specifying -ReuseSourceFolderStructure.
        The same structure on the SOURCE will be kept exactly, so consider this if you're migrating between different versions and use part of Microsoft's default Sql structure (MSSql12.INSTANCE, etc)
        
        *Note, to reuse destination folder structure, specify -WithReplace
    
    .PARAMETER DestinationFilePrefix
        This value will be prefixed to ALL restored files (log and data). This is just a simple string prefix. If you want to perform more complex rename operations then please use the FileMapping parameter
        
        This will apply to all file move options, except for FileMapping
    
    .PARAMETER DestinationFileSuffix
        This value will be suffixed to ALL restored files (log and data). This is just a simple string suffix. If you want to perform more complex rename operations then please use the FileMapping parameter
        
        This will apply to all file move options, except for FileMapping
    
    .PARAMETER RestoredDatababaseNamePrefix
        A string which will be prefixed to the start of the restore Database's Name
        Useful if restoring a copy to the same sql sevrer for testing.
    
    .PARAMETER TrustDbBackupHistory
        This switch can be used when piping the output of Get-DbaBackupHistory or Backup-DbaDatabase into this command.
        It allows the user to say that they trust that the output from those commands is correct, and skips the file header read portion of the process. This means a faster process, but at the risk of not knowing till halfway through the restore that something is wrong with a file.
    
    .PARAMETER MaxTransferSize
        Parameter to set the unit of transfer. Values must be a multiple by 64kb
    
    .PARAMETER Blocksize
        Specifies the block size to use. Must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb or 64kb
        Can be specified in bytes
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail
    
    .PARAMETER BufferCount
        Number of I/O buffers to use to perform the operation.
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail
    
    .PARAMETER XpNoRecurse
        If specified, prevents the XpDirTree process from recursing (its default behaviour)

	.PARAMETER DirectoryRecurse
		If specified the specified directory will be recursed into
	
	.PARAMETER	Continue
		If specified we will to attempt to recover more transaction log backups onto  database(s) in Recovering or Standby states

	.PARAMETER StandbyDirectory
		If a directory is specified the database(s) will be restored into a standby state, with the standby file placed into this directory (which must exist, and be writable by the target Sql Server instance)

	.PARAMETER AzureCredential
		The name of the SQL Server credential to be used if restoring from an Azure hosted backup

    .PARAMETER ReplaceDbNameInFile
        If switch set and occurence of the original database's name in a data or log file will be replace with the name specified in the Databasename paramter
        
	.PARAMETER Silent
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.
    
	.PARAMETER Confirm
        Prompts to confirm certain actions
    
    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command
    
    .EXAMPLE
        Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups
        
        Scans all the backup files in \\server2\backups, filters them and restores the database to server1\instance1
    
    .EXAMPLE
        Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -MaintenanceSolutionBackup -DestinationDataDirectory c:\restores
        
        Scans all the backup files in \\server2\backups$ stored in an Ola Hallengren style folder structure,
        filters them and restores the database to the c:\restores folder on server1\instance1
    
    .EXAMPLE
        Get-ChildItem c:\SQLbackups1\, \\server\sqlbackups2 | Restore-DbaDatabase -SqlInstance server1\instance1
        
        Takes the provided files from multiple directories and restores them on  server1\instance1
    
    .EXAMPLE
        $RestoreTime = Get-Date('11:19 23/12/2016')
        Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -MaintenanceSolutionBackup -DestinationDataDirectory c:\restores -RestoreTime $RestoreTime
        
        Scans all the backup files in \\server2\backups stored in an Ola Hallengren style folder structure,
        filters them and restores the database to the c:\restores folder on server1\instance1 up to 11:19 23/12/2016
    
    .EXAMPLE
        Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -DestinationDataDirectory c:\restores -OutputScriptOnly | Select-Object -ExpandPropert Tsql | Out-File -Filepath c:\scripts\restore.sql
        
        Scans all the backup files in \\server2\backups stored in an Ola Hallengren style folder structure,
        filters them and generate the T-SQL Scripts to restore the database to the latest point in time,
        and then stores the output in a file for later retrieval
    
    .EXAMPLE
        Restore-DbaDatabase -SqlInstance server1\instance1 -Path c:\backups -DestinationDataDirectory c:\DataFiles -DestinationLogDirectory c:\LogFile
        
        Scans all the files in c:\backups and then restores them onto the SQL Server Instance server1\instance1, placing data files
        c:\DataFiles and all the log files into c:\LogFiles
    
	.EXAMPLE 
		Restore-DbaDatabase -SqlInstance server1\instance1 -Path http://demo.blob.core.windows.net/backups/dbbackup.bak -AzureCredential MyAzureCredential

		Will restore the backup held at  http://demo.blob.core.windows.net/backups/dbbackup.bak to server1\instance1. The connection to Azure will be made using the 
		credential MyAzureCredential held on instance Server1\instance1
		
    .EXAMPLE
        $File = Get-ChildItem c:\backups, \\server1\backups -recurse
        $File | Restore-DbaDatabase -SqlInstance Server1\Instance -useDestinationDefaultDirectories
        
        This will take all of the files found under the folders c:\backups and \\server1\backups, and pipeline them into
        Restore-DbaDatabase. Restore-DbaDatabase will then scan all of the files, and restore all of the databases included
        to the latest point in time covered by their backups. All data and log files will be moved to the default SQL Sever
        folder for those file types as defined on the target instance.

	.EXAMPLE
		$files = Get-ChildItem C:\dbatools\db1

		#Restore database to a point in time
		$files | Restore-DbaDatabase -SqlServer server\instance1 `
					-DestinationFilePrefix prefix -DatabaseName Restored  `
					-RestoreTime (get-date "14:58:30 22/05/2017") `
					-NoRecovery -WithReplace -StandbyDirectory C:\dbatools\standby 

		#It's in standby so we can peek at it
		Invoke-DbaSqlCmd -ServerInstance server\instance1 -Query "select top 1 * from Restored.dbo.steps order by dt desc"

		#Not quite there so let's roll on a bit:
		$files | Restore-DbaDatabase -SqlServer server\instance1 `
					-DestinationFilePrefix prefix -DatabaseName Restored `
					-continue -WithReplace -RestoreTime (get-date "15:09:30 22/05/2017") `
					-StandbyDirectory C:\dbatools\standby

		Invoke-DbaSqlCmd -ServerInstance server\instance1 -Query "select top 1 * from restored.dbo.steps order by dt desc"

		Restore-DbaDatabase -SqlServer server\instance1 `
					-DestinationFilePrefix prefix -DatabaseName Restored `
					-continue -WithReplace 
		
		In this example we step through the backup files held in c:\dbatools\db1 folder.
		First we restore the database to a point in time in standby mode. This means we can check some details in the databases
		We then roll it on a further 9 minutes to perform some more checks
		And finally we continue by rolling it all the way forward to the latest point in the backup.
		At each step, only the log files needed to roll the database forward are restored.
    
    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Original Author: Stuart Moore (@napalmgram), stuart-moore.com
        
        dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
        Copyright (C) 2016 Chrissy LeMaire
        
        This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
        
        This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
        
        You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$Path,
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential,
        [string[]]$DatabaseName,
        [string[]]$SourceInstance,
        [Switch]$XpDirTree,
        [switch]$Recurse,
        [switch]$silent
      
    )
    begin {
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Debug -Message "Parameters bound: $($PSBoundParameters.Keys -join ", ")"

        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        $Files = @()
        if ($XpDirTree -eq $true){
            ForEach ($f in $path) {
                $Files += Get-XpDirTreeRestoreFile -Path $f -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            }
        } 
        else {
            ForEach ($f in $path) {
                $Files += Get-ChildItem -Path $f -file -Recurse:$recurse
            }
        }
        
        $FileDetails = $Files | Read-DbaBackupHeader -SqlInstance localhost\sqlexpress2016
        if (Was-Bound 'SourceInstance') {
            $FileDetails = $FileDetails | Where-Object {$_.ServerName -in $SourceInstance}
        }

        if (Was-Bound 'DatabaseName') {
            $FileDetails = $FileDetails | Where-Object {$_.DatabaseName -in $DatabaseName}
        }

        $groupdetails = $FileDetails | group-object -Property BackupSetGUID
        $groupResults = @()
        Foreach ($Group in $GroupDetails){
            $historyObject = New-Object Sqlcollaborative.Dbatools.Database.BackupHistory
            $historyObject.ComputerName = $group.group[0].MachineName
            $historyObject.InstanceName = $group.group[0].ServiceName
            $historyObject.SqlInstance = $group.group[0].ServerName
            $historyObject.Database = $group.Group[0].DatabaseName
            $historyObject.UserName = $group.Group[0].UserName
            $historyObject.Start = [DateTime]$group.Group[0].BackupStartDate
            $historyObject.End = [DateTime]$group.Group[0].BackupFinishDate
            $historyObject.Duration = ([DateTime]$group.Group[0].BackupFinishDate - [DateTime]$group.Group[0].BackupStartDate).Seconds
            $historyObject.Path = $Group.Group.BackupPath
            $historyObject.TotalSize = (Measure-Object $Group.Group.BackupSizeMB -sum).sum
            $historyObject.Type = $group.Group[0].BackupTypeDescription
            $historyObject.BackupSetId = $group[0].BackupSetGUID
            $historyObject.DeviceType = 'Disk'
            $historyObject.FullName = $Group.Group.BackupPath
            $historyObject.FileList = $Group.Group[0].FileList
            $historyObject.Position = $group.Group[0].Position
            $historyObject.FirstLsn = $group.Group[0].FirstLSN
            $historyObject.DatabaseBackupLsn = $group.Group[0].DatabaseBackupLSN
            $historyObject.CheckpointLsn = $group.Group[0].CheckpointLSN
            $historyObject.LastLsn = $group.Group[0].LastLsn
            $historyObject.SoftwareVersionMajor = $group.Group[0].SoftwareVersionMajor
            $groupResults += $historyObject
        }
        $groupResults | Sort-Object -Property End -Descending
    }

    
}