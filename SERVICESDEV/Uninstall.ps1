#requires -RunAsAdministrator
$serviceName = 'ServicesDev'
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $serviceName | Out-Null
    Write-Host 'Servicio ServicesDev eliminado. Los archivos y bitácoras se conservaron.'
} else {
    Write-Host 'El servicio no está instalado.'
}
