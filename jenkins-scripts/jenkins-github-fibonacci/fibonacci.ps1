param(
    [int]$N = 10
)

$a = 0
$b = 1

Write-Host "The Fibonacci series is :"

for ($i = 0; $i -lt $N; $i++) {
    Write-Host "$i`t$a"
    $fn = $a + $b
    $a = $b
    $b = $fn
}
