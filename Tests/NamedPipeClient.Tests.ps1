$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\..\NamedPipes.psm1" -Force

Describe "NamedPipeClient" {
	It "New-NamedPipeClient returns a [NamedPipeClient]"{
		$PipeName = "NamedPipeClient-Test-$((Get-Date).ToFileTime())"
		
		# We need to open a pipe server before we can create a client
		$serverPipe = New-Object System.IO.Pipes.NamedPipeServerStream $PipeName, InOut, 1, Byte, Asynchronous, 1024, 1024
		
		$Client = New-NamedPipeClient $PipeName
		$Client.Close()
		
		$serverPipe.Close()
		$Client.GetType().FullName | Should Be "NamedPipeClient"
	}
	
	
	It "closes the pipe" {
		$PipeName = "NamedPipeClient-Test-$((Get-Date).ToFileTime())"
		
		$serverPipe = New-Object System.IO.Pipes.NamedPipeServerStream $PipeName, InOut, 1, Byte, Asynchronous, 1024, 1024
		$Client = New-NamedPipeClient $PipeName
		
		$Client._clientPipe.IsConnected | Should Be $false
		
		$Client.Connect();
		
		$Client._clientPipe.IsConnected | Should Be $true
		
		$Client.Close()
		
		$Client._clientPipe.IsConnected | Should Be $false
		
		$serverPipe.Close()
	}
	
	
	It "reads data from server" {
		$PipeName = "NamedPipeClient-Test-$((Get-Date).ToFileTime())"
		$RepliedWithDataEvent = New-Object System.Threading.ManualResetEvent($false)
		
		$JobScriptBlock = {
			Param(
				[String]$PipeName
			)
			$ServerPipe = New-Object System.IO.Pipes.NamedPipeServerStream $PipeName, InOut, 1, Byte, Asynchronous, 1024, 1024
			$ServerPipe.WaitForConnection();

			$ClientWriter = New-Object System.IO.StreamWriter($ServerPipe)
			$ClientWriter.AutoFlush = $true
			$ClientWriter.Write("0123456789abcdef");
			$ServerPipe.Close()
		}
		$ServerJob = Start-Job -ScriptBlock $JobScriptBlock -ArgumentList $PipeName
		
		$Client = New-NamedPipeClient $PipeName
		$Client.Connect(2000); # What is the correct async way to do this???
		$Client.BeginRead({
			Param(
				[string]$Message,
				[NamedPipeClient]$PipeInstance
			)
			if ($Message -eq "0123456789abcdef") {
				$RepliedWithDataEvent.Set();
			}
		});
		
		for($i = 0; $i -lt 100; $i++){
			$RepliedWithDataEventWasSet = $RepliedWithDataEvent.WaitOne(10);
			if ($RepliedWithDataEventWasSet) { break }
		}
		
		$Client.Close()
		$ServerJob | Remove-Job -Force
		
		$RepliedWithDataEventWasSet | Should Be $True
	}


	It "sends and receives the same data back" {
		$TestMessage = "0123456789abcdef♠🙈🙉🙊"
		
		$PipeName = "NamedPipeClient-Test-$((Get-Date).ToFileTime())"
		$RepliedWithDataEvent = New-Object System.Threading.ManualResetEvent($false)
		
		$JobScriptBlock = {
			Param(
				[String]$PipeName
			)
			$ServerPipe = New-Object System.IO.Pipes.NamedPipeServerStream $PipeName, InOut, 1, Byte, Asynchronous, 1024, 1024
			$ServerPipe.WaitForConnection();

			$ClientReader = New-Object System.IO.StreamReader($ServerPipe, [System.Text.Encoding]::UTF8); 
			$Message = $ClientReader.ReadLine()
			
			$ClientWriter = New-Object System.IO.StreamWriter($ServerPipe)
			$ClientWriter.AutoFlush = $true
			$ClientWriter.Write($Message);
			
			$ServerPipe.Close()
		}
		$ServerJob = Start-Job -ScriptBlock $JobScriptBlock -ArgumentList $PipeName
		
		$Client = New-NamedPipeClient $PipeName
		$Client.Connect(2000); # What is the correct async way to do this???
		
		$Client.BeginWrite("$TestMessage`n"); # ReadLine needs a line ending
		$Client.BeginRead({
			Param(
				[string]$Message,
				[NamedPipeClient]$PipeInstance
			)
			if ($Message -eq $TestMessage) {
				$RepliedWithDataEvent.Set();
			}
		});
		
		for($i = 0; $i -lt 200; $i++){
			$DataEventWasSet = $RepliedWithDataEvent.WaitOne(10);
			if ($DataEventWasSet) { break }
		}
		$ServerJob | Remove-Job -Force
		$DataEventWasSet | Should Be $True
	}
}