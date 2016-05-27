$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\..\PSNamedPipes.psm1" -Force

Describe "NamedPipeServer" {
	It "New-NamedPipeServer returns a [NamedPipeServer]" {
		$PipeName = "NamedPipeServer-Test-$((Get-Date).ToFileTime())"
		$a = New-NamedPipeServer $PipeName
		$a.Close()
		$a.GetType().FullName | Should Be "NamedPipeServer"
	}
	
	
	It "closes the pipe" {
		$PipeName = "NamedPipeServer-Test-$((Get-Date).ToFileTime())"
		$a = New-NamedPipeServer $PipeName
		$a.Close()
		
		$ClientPipe = New-Object System.IO.Pipes.NamedPipeClientStream($PipeName)
		{ $ClientPipe.Connect(10) } | Should Throw "The operation has timed out."
	}
	

	It "calls the OnConnected callback" {
		$PipeName = "NamedPipeServer-Test-$((Get-Date).ToFileTime())"
		$WaitForConnectionEvent = New-Object System.Threading.ManualResetEvent($false)
		
		$a = New-NamedPipeServer $PipeName
		$a.BeginWaitForConnection({
			$WaitForConnectionEvent.Set();
		})

		$JobScriptBlock = {
			Param(
				[String]$PipeName
			)
			$ClientPipe = New-Object System.IO.Pipes.NamedPipeClientStream($PipeName)
			$ClientPipe.Connect(30000)
			$ClientPipe.Close()
		}
		$ClientJob = Start-Job -ScriptBlock $JobScriptBlock -ArgumentList $PipeName
	
		# We have to spin for a bit. If we issue a one long WaitOne() call this thread will be blocked and the event handler 
		# will get called only after the event times out (which is not correct)
		for($i = 0; $i -lt 300; $i++){
			$ConnectedEventWasSet = $WaitForConnectionEvent.WaitOne(100);
			if ($ConnectedEventWasSet) { break }
		}
		
		$a.IsConnected() | Should Be $True
		$a.Close()

		$ClientJob | Remove-Job -Force
		$ConnectedEventWasSet | Should Be $True
	}


	It "reads data from client" {
		$PipeName = "NamedPipeServer-Test-$((Get-Date).ToFileTime())"
		$RepliedWithDataEvent = New-Object System.Threading.ManualResetEvent($false)
		
		$a = New-NamedPipeServer $PipeName

		$JobScriptBlock = {
			Param(
				[String]$PipeName
			)
			$ClientPipe = New-Object System.IO.Pipes.NamedPipeClientStream($PipeName)
			$ClientPipe.Connect(30000)

			$ClientWriter = New-Object System.IO.StreamWriter($ClientPipe)
			$ClientWriter.AutoFlush = $true
			$ClientWriter.Write("0123456789abcdef");
			$ClientPipe.Close()
		}
		$ClientJob = Start-Job -ScriptBlock $JobScriptBlock -ArgumentList $PipeName
		
		$a.WaitForConnection();
		$a.IsConnected() | Should Be $True

		# The client has connected, let's read something
		$a.BeginRead({
			Param(
				[string]$Message,
				[NamedPipeServer]$PipeInstance
			)
			if ($Message -eq "0123456789abcdef") {
				$RepliedWithDataEvent.Set();
			}
		});


		# We have to spin for a bit, if we issue a one long WaitOne() call the event handler might not get called due to thread timing
		for($i = 0; $i -lt 300; $i++){
			$DataEventWasSet = $RepliedWithDataEvent.WaitOne(100);
			if ($DataEventWasSet) { break }
		}
		$DataEventWasSet | Should Be $True

		$a.Close()
		$ClientJob | Remove-Job -Force
	}


	It "sends and receives the same data back" {
		$TestMessage = "0123456789abcdef♠🙈🙉🙊"

		$PipeName = "NamedPipeServer-Test-$((Get-Date).ToFileTime())"
		$WaitForConnectionEvent = New-Object System.Threading.ManualResetEvent($false)
		$RepliedWithDataEvent = New-Object System.Threading.ManualResetEvent($false)
		
		$a = New-NamedPipeServer $PipeName
		$a.BeginWaitForConnection({$WaitForConnectionEvent.Set() })

		$JobScriptBlock = {
			Param(
				[String]$PipeName
			)
			$ClientPipe = New-Object System.IO.Pipes.NamedPipeClientStream($PipeName)
			$ClientPipe.Connect(30000)

			$ClientReader = New-Object System.IO.StreamReader($ClientPipe, [System.Text.Encoding]::UTF8); 
			$Message = $ClientReader.ReadLine()
			
			$ClientWriter = New-Object System.IO.StreamWriter($ClientPipe)
			$ClientWriter.AutoFlush = $true
			$ClientWriter.Write($Message);

			$ClientPipe.Close()
		}

		$ClientJob = Start-Job -ScriptBlock $JobScriptBlock -ArgumentList $PipeName

		# We have to spin for a bit. If we issue a one long WaitOne() call this thread will be blocked and the event handler 
		# will get called only after the event times out (which is not correct)
		for($i = 0; $i -lt 300; $i++){
			$ConnectedEventWasSet = $WaitForConnectionEvent.WaitOne(100);
			if ($ConnectedEventWasSet) { break }
		}
		$ConnectedEventWasSet | Should Be $True

		$a.BeginWrite("$TestMessage`n"); # ReadLine needs a line ending
		# The client has connected, let's read something
		$a.BeginRead({
			Param(
				[string]$Message,
				[NamedPipeServer]$PipeInstance
			)
			if ($Message -eq $TestMessage) {
				$RepliedWithDataEvent.Set();
			}
		});

		# We have to spin for a bit. If we issue a one long WaitOne() call this thread will be blocked and the event handler 
		# will get called only after the event times out (which is not correct)
		for($i = 0; $i -lt 300; $i++){
			$DataEventWasSet = $RepliedWithDataEvent.WaitOne(100);
			if ($DataEventWasSet) { break }
		}
		$ClientJob | Remove-Job -Force
		$DataEventWasSet | Should Be $True
	}
	
}
