# sqldeep-audit
Monitoring Microsoft Windows and MSSQL instance related performance counters.
With this script you can collect OS and MSSQL level perfmon counters and visualize them via power bi dashboard template named "SQLDeepAudit-Monitoring.pbit"

Thankfully, This script is based on Rob Barat article (https://www.aussierobsql.com/using-powershell-to-setup-performance-monitor-data-collector-sets/)

## Syntax:
	.\SqlDeepAudit.ps1 [-UI] -PerfmonCred [-ServerName] [-ServerFilePath] [-InstanceFilePath] [-ODBC <odbc_parameters>]
	
	<odbc_parameters> ::=
	{
		[-ODBCName]
		-SqlServerInstance
		[-SqlServerInstanceDB]
		-SqlServerInstanceCred
	}

	**Description:**
	SqlDeepAudit will monitor some important server and microsoft sql server performance counters.
	These counters can be extend via modifing "SQLDeepAudit-Server.xml" and "SQLDeepAudit-Instance.xml" files.
	
	**Arguments:**
	-UI. You can run script by using only this switch. with this switch script will run in interactve mode and ask all parameter values via console interface.
	-PerfmonCred. You should specify a Credential for perfmon to collecting counters by that account.
	-ServerName. You can specify name of machine that you want to monitor, default value is current machine name.
	-ServerFilePath. You can specify XML file path that contain OS level counters via this parameter, default value is "<current_location>\SqlDeepAudit-Server.xml"
	-InstanceFilePath. You can specify XML file path that contain SQL level counters via this parameter, default value is "<current_location>\SqlDeepAudit-Instance.xml"
	-ODBC. This switch force Perfmon app to save collected counters into a Sql Server table via an ODBC connection.
	-ODBCName. If -ODBC switch is used, you can set specific DSN name for your ODBC connection, but if you dont set any name for this parameter default value will be used. default is "DBA".
	-SqlServerInstance. If -ODBC switch is used, you should specify Microsoft SQL Server Instance name that used by ODBC connection to store counters data on it.
	-SqlServerInstanceDB. If -ODBC switch is used, you can specify existed Database name inside the SqlServerInstance to create appropriate tables for collectiong perfmon data on it. default database name is "DBA".
	-SqlServerInstanceCred. If -ODBC switch is used, you should specify a Credential that is used by ODBC dsn to connect to SqlServerInstance.
	
	**Examples:**
	**A.Collecting counters on disk via interactive questions.**
	In this scenario data will collected on C:\Perfmon folder. Also "SQLDeepAudit-Server.xml" and "SQLDeepAudit-Instance.xml" file contain our counters that saved in same directory as SqlDeepAudit.ps1.
	.\SqlDeepAudit.ps1 -UI

	**B.Collecting counters to sql server database tables via interactive questions.**
	In this scenario data will collected on C:\Perfmon folder and also in sql server via and ODBC connection. Also "SQLDeepAudit-Server.xml" and "SQLDeepAudit-Instance.xml" file contain our counters that saved in same directory as SqlDeepAudit.ps1.
	.\SqlDeepAudit.ps1 -UI -ODBC
	
	**C.Collecting counters on disk in silent mode (not interactive mode).**
	In this scenario data will collected on C:\Perfmon folder and counters collecting as "user01" privilages. Also "SQLDeepAudit-Server.xml" and "SQLDeepAudit-Instance.xml" file contain our counters that saved in same directory as SqlDeepAudit.ps1.
	.\SqlDeepAudit.ps1 -ServerName "SRV01" -PerfmonCred "user01"	

	**D.Collecting counters to sql server database tables in silent mode (not interactive mode).**
	In this scenario data will collected on C:\Perfmon folder and also in sql server instance named "SRV20\WEB" that listen on static customized port of 49200 (instead of default 1433). counters collecting as "user01" privilages. Also "SQLDeepAudit-Server.xml" and "SQLDeepAudit-Instance.xml" files contain our counters that saved in same directory as SqlDeepAudit.ps1 and collected countrs will be insert in specified SqlServerInstance database named "DBA" via "domain\dbuser01" credential.
	.\SqlDeepAudit.ps1 -ServerName "SRV01" -PerfmonCred "domain\user01" -ODBC -SqlServerInstance "SRV20\WEB,49200" -SqlServerInstanceCred "domain\dbuser01"
