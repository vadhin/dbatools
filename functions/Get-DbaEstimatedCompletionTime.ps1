﻿Function Get-DbaEstimatedCompletionTime {
<#
.SYNOPSIS
Gets execution and estimated completion time information for queries
	
.DESCRIPTION
Gets execution and estimated completion time information for queries

Percent complete will show for the following commands
	
ALTER INDEX REORGANIZE
AUTO_SHRINK option with ALTER DATABASE
BACKUP DATABASE
DBCC CHECKDB
DBCC CHECKFILEGROUP
DBCC CHECKTABLE
DBCC INDEXDEFRAG
DBCC SHRINKDATABASE
DBCC SHRINKFILE
RECOVERY
RESTORE DATABASE
ROLLBACK
TDE ENCRYPTION
	
For additional information, check out https://blogs.sentryone.com/loriedwards/patience-dm-exec-requests/ and https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-requests-transact-sql
	
.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
SqlCredential object used to connect to the SQL Server as a different user.

.PARAMETER Database
The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

.PARAMETER Exclude
The database(s) to exclude - this list is autopopulated from the server

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages.

.NOTES
Tags: Database
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-DbaEstimatedCompletionTime

.EXAMPLE
Get-DbaEstimatedCompletionTime -SqlInstance sql2016
	
Gets estimated completion times for queries performed against the entire server
	
.EXAMPLE
Get-DbaEstimatedCompletionTime -SqlInstance sql2016 | Select *
	
Gets estimated completion times for queries performed against the entire server PLUS the SQL query text of each command

.EXAMPLE
Get-DbaEstimatedCompletionTime -SqlInstance sql2016 | Where-Object { $_.Text -match 'somequerytext' }
	
Gets results for commands whose queries only match specific text (match is like LIKE but way more powerful)

.EXAMPLE
Get-DbaEstimatedCompletionTime -SqlInstance sql2016 -Databases Northwind,pubs,Adventureworks2014

Gets estimated completion times for queries performed against the Northwind, pubs, and Adventureworks2014 databases

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[PsCredential]$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$Exclude,
		[switch]$Silent
	)
	
	begin {
		$sql = "SELECT
				DB_NAME(r.database_id) as [Database],
				USER_NAME(r.user_id) as [Login],
				Command,
				start_time as StartTime,
				percent_complete as PercentComplete,
				
				  RIGHT('00000' + CAST(((DATEDIFF(s,start_time,GetDate()))/3600) as varchar), 
								CASE 
									WHEN LEN(((DATEDIFF(s,start_time,GetDate()))/3600)) < 2 THEN 2 
									ELSE LEN(((DATEDIFF(s,start_time,GetDate()))/3600)) 
								 END)  + ':'
				+ RIGHT('00' + CAST((DATEDIFF(s,start_time,GetDate())%3600)/60 as varchar), 2) + ':'
				+ RIGHT('00' + CAST((DATEDIFF(s,start_time,GetDate())%60) as varchar), 2) as RunningTime,
				
				  RIGHT('00000' + CAST((estimated_completion_time/3600000) as varchar), 
						CASE 
									WHEN LEN((estimated_completion_time/3600000)) < 2 THEN 2 
									ELSE LEN((estimated_completion_time/3600000)) 
						 END)  + ':'
				+ RIGHT('00' + CAST((estimated_completion_time %3600000)/60000 as varchar), 2) + ':'
				+ RIGHT('00' + CAST((estimated_completion_time %60000)/1000 as varchar), 2) as EstimatedTimeToGo,
				dateadd(second,estimated_completion_time/1000, getdate()) as EstimatedCompletionTime,
				s.Text
		 	FROM sys.dm_exec_requests r
			CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) s"
	}
	
	process {
		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Connecting to $instance"
			try {
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $SqlCredential
				
			}
			catch {
				Stop-Function -Message "Can't connect to $instance. Moving on." -Continue
			}
			
			if ($database) {
				$includedatabases = $database -join "','"
				$sql = "$sql WHERE DB_NAME(r.database_id) in ('$includedatabases')"
			}
			
			if ($exclude) {
				$excludedatabases = $exclude -join "','"
				$sql = "$sql WHERE DB_NAME(r.database_id) not in ('$excludedatabases')"
			}
			
			Write-Message -Level Debug -Message $sql
			#Invoke-DbaSqlcmd -ServerInstance $instance -Credential $SqlCredential -Query $sql | Select-DefaultView -ExcludeProperty Text
			foreach ($row in (Invoke-DbaSqlcmd -ServerInstance $instance -Credential $SqlCredential -Query $sql)) {
				[pscustomobject]@{
					ComputerName = $server.NetName
					InstanceName = $server.ServiceName
					SqlInstance = $server.DomainInstanceName
					Database = $row.Database
					Login = $row.Login
					Command = $row.Command
					PercentComplete = $row.PercentComplete
					StartTime = $row.StartTime
					RunningTime = $row.RunningTime
					EstimatedTimeToGo = $row.EstimatedTimeToGo
					EstimatedCompletionTime = $row.EstimatedCompletionTime
					Text = $row.Text
				} | Select-DefaultView -ExcludeProperty Text
			}
		}
	}
}

