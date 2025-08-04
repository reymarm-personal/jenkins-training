param(
    [int]$N = 10
)

# Initialize variables
$a = 0
$b = 1
Invoke-Command -ComputerName USEADVVT1DB1 -ScriptBlock {hostname}
Write-Host "The Fibonacci series is :"

# Generate Fibonacci sequence
for ($i = 0; $i -lt $N; $i++) {
    Write-Host "$i`t$a"
    $fn = $a + $b
    $a = $b
    $b = $fn
}
