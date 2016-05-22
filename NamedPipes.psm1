$ErrorActionPreference = "Stop"

if (-not ("CallbackEventBridge" -as [type])) {
	Add-Type @"
		using System;
		public sealed class CallbackEventBridge
		{
			public event AsyncCallback CallbackComplete = delegate {};
			private void CallbackInternal(IAsyncResult result)
			{
				CallbackComplete(result);
			}
			public AsyncCallback Callback
			{
				get { return new AsyncCallback(CallbackInternal); }
			}
		}
"@}

class NamedPipeServer {

	hidden [System.IO.Pipes.NamedPipeServerStream]$_serverPipe = $null;
	hidden $_readBuffer = $null;

	hidden $_OnConnectedCallbackBridge = $null; # this is our internal async event bridge
	hidden [System.Management.Automation.ScriptBlock]$_OnConnectedScriptBlock = {}; # this is the scriptblock the user wants to call

	hidden $_OnDataAvailableCallbackBridge = $null; # this is our internal async event bridge
	hidden [System.Management.Automation.ScriptBlock]$_OnDataAvailableScriptBlock = {}; # this is the scriptblock the user wants to call


	hidden $_OnDataWrittenCallbackBridge = $null; # this is our internal async event bridge

	# Constructor
	NamedPipeServer ([string]$PipeName){
		$this._readBuffer = New-Object byte[] 1024
		$this._serverPipe = New-Object System.IO.Pipes.NamedPipeServerStream $PipeName, InOut, 1, Byte, Asynchronous, 1024, 1024
		
		# Create a bridge for OnConnected async events
		$this._OnConnectedCallbackBridge = New-Object CallbackEventBridge
		Register-ObjectEvent -InputObject $this._OnConnectedCallbackBridge -EventName CallbackComplete `
			-Action {
				param($asyncResult)
				$asyncResult.AsyncState.OnClientConnected.Invoke($asyncResult);
			} > $null


		# Create a bridge for OnDataAvailable async events
		$this._OnDataAvailableCallbackBridge = New-Object CallbackEventBridge
		Register-ObjectEvent -InputObject $this._OnDataAvailableCallbackBridge -EventName CallbackComplete `
			-Action {
				param($asyncResult)
				$asyncResult.AsyncState.OnDataAvailable.Invoke($asyncResult);
			} > $null


		# Create a bridge for OnDataWritten async events
		$this._OnDataWrittenCallbackBridge = New-Object CallbackEventBridge
		Register-ObjectEvent -InputObject $this._OnDataWrittenCallbackBridge -EventName CallbackComplete `
			-Action {
				param($asyncResult)
				$asyncResult.AsyncState.OnDataWritten.Invoke($asyncResult);
			} > $null
	}
 

	
	[void]WaitForConnection(){
		$this._serverPipe.WaitForConnection();
	}
	[void]BeginWaitForConnection([System.Management.Automation.ScriptBlock]$Callback = {}){
		$this._OnConnectedScriptBlock = $Callback; # Save the script the user wants to call on connect
		$this._serverPipe.BeginWaitForConnection($this._OnConnectedCallbackBridge.Callback, $this);
	}
	hidden [void]OnClientConnected($asyncResult){
		$this._serverPipe.EndWaitForConnection($asyncResult)
		$this._OnConnectedScriptBlock.Invoke();
	}



	[void]BeginRead([System.Management.Automation.ScriptBlock]$Callback){
		$this._OnDataAvailableScriptBlock = $Callback; # Save the script the user wants to call when data is available
		$this._serverPipe.BeginRead($this._readBuffer, 0, $this._readBuffer.Length, $this._OnDataAvailableCallbackBridge.Callback, $this)
	}
	hidden [void]OnDataAvailable($asyncResult){
		$MessageLength = $this._serverPipe.EndRead($asyncResult)

		if ($MessageLength -gt 0){
			$PipeText = [System.Text.Encoding]::UTF8.GetString($this._readBuffer, 0, $MessageLength)
			$this._OnDataAvailableScriptBlock.Invoke($PipeText, $this);
			$this.BeginRead($this._OnDataAvailableScriptBlock);
		} else {
			# Pipe was closed
			#Write-Verbose "Pipe closed" -ForegroundColor Red
		}
	}


	[void]BeginWrite([string]$Message){
		$_writeBufferLocal = [System.Text.Encoding]::UTF8.GetBytes($Message)
		$this._serverPipe.BeginWrite($_writeBufferLocal, 0, $_writeBufferLocal.Length, $this._OnDataWrittenCallbackBridge.Callback, $this)
	}
	hidden [void]OnDataWritten($asyncResult){
		$asyncResult._serverPipe.EndWrite($asyncResult)
	}


	[Boolean] IsConnected(){
		return $this._serverPipe.IsConnected
	}

	Close (){
		$this._serverPipe.Close();
	}
}

class NamedPipeClient{
	hidden [System.IO.Pipes.NamedPipeClientStream]$_clientPipe = $null;
	hidden $_readBuffer = $null;
	
	hidden $_OnDataAvailableCallbackBridge = $null; # this is our internal async event bridge
	hidden [System.Management.Automation.ScriptBlock]$_OnDataAvailableScriptBlock = {}; # this is the scriptblock the user wants to call
	
	hidden $_OnDataWrittenCallbackBridge = $null; # this is our internal async event bridge
	
	
	NamedPipeClient ([string]$PipeName){
		[string]$PipeServer = "."
		$this._readBuffer = New-Object byte[] 1024
		$this._clientPipe = New-Object System.IO.Pipes.NamedPipeClientStream $PipeServer, $PipeName, InOut, Asynchronous
		
		# Create a bridge for OnDataAvailable async events
		$this._OnDataAvailableCallbackBridge = New-Object CallbackEventBridge
		Register-ObjectEvent -InputObject $this._OnDataAvailableCallbackBridge -EventName CallbackComplete `
			-Action {
				param($asyncResult)
				$asyncResult.AsyncState.OnDataAvailable.Invoke($asyncResult);
			} > $null
		
		# Create a bridge for OnDataWritten async events
		$this._OnDataWrittenCallbackBridge = New-Object CallbackEventBridge
		Register-ObjectEvent -InputObject $this._OnDataWrittenCallbackBridge -EventName CallbackComplete `
			-Action {
				param($asyncResult)
				$asyncResult.AsyncState.OnDataWritten.Invoke($asyncResult);
			} > $null
	}
	
	[void]BeginRead([System.Management.Automation.ScriptBlock]$Callback){
		$this._OnDataAvailableScriptBlock = $Callback; # Save the script the user wants to call when data is available
		$this._clientPipe.BeginRead($this._readBuffer, 0, $this._readBuffer.Length, $this._OnDataAvailableCallbackBridge.Callback, $this)
	}
	hidden [void]OnDataAvailable($asyncResult){
		$MessageLength = $this._clientPipe.EndRead($asyncResult)

		if ($MessageLength -gt 0){
			$PipeText = [System.Text.Encoding]::UTF8.GetString($this._readBuffer, 0, $MessageLength)
			$this._OnDataAvailableScriptBlock.Invoke($PipeText, $this);
			$this.BeginRead($this._OnDataAvailableScriptBlock);
		} else {
			# Pipe was closed
			#Write-Verbose "Pipe closed" -ForegroundColor Red
		}
	}
	
	[void]BeginWrite([string]$Message){
		$_writeBufferLocal = [System.Text.Encoding]::UTF8.GetBytes($Message)
		$this._clientPipe.BeginWrite($_writeBufferLocal, 0, $_writeBufferLocal.Length, $this._OnDataWrittenCallbackBridge.Callback, $this)
	}
	hidden [void]OnDataWritten($asyncResult){
		$asyncResult._clientPipe.EndWrite($asyncResult)
	}
	
	Connect([int]$Timeout = 100){
		$this._clientPipe.Connect($Timeout);
	}
	
	Connect(){
		$this._clientPipe.Connect(100);
	}
	
	Close (){
		$this._clientPipe.Close();
	}
}

# We need this function because our classes are not visible outside the module
function New-NamedPipeServer{
	Param(
		[string]$PipeName
	)
	
	return [NamedPipeServer]::new($PipeName)
}
Export-ModuleMember New-NamedPipeServer

# We need this function because our classes are not visible outside the module
function New-NamedPipeClient{
	Param(
		[string]$PipeName
	)
	
	return [NamedPipeClient]::new($PipeName)
}
Export-ModuleMember New-NamedPipeClient
