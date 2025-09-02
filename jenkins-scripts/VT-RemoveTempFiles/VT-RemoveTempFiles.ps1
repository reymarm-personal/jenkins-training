Remove Temp Files and Directory more than 30 days - working code
 
# Define the path to the directory you want to clean up
$targetPath = "C:\Program Files\Deltek\Vantagepoint\Temp"
# Define the age limit in days (e.g., 30 days)
$daysToKeep = 30
# Calculate the cutoff date
$cutoffDate = (Get-Date).AddDays(-$daysToKeep)
Write-Host "Searching for files and directories older than $daysToKeep days in: $targetPath"
Write-Host "Cutoff date for items: $cutoffDate"
# Get files and directories older than the cutoff date
# -Recurse: Ensures all items (files and directories) within subdirectories are also considered.
# -Exclude: (Optional) Add patterns here if you want to exclude specific files or folders.
$itemsToDelete = Get-ChildItem -Path $targetPath -Recurse | Where-Object { $_.LastWriteTime -lt $cutoffDate }
# Filter out the root directory itself if it matches the criteria (we only want its contents)
# This prevents the script from trying to delete the targetPath itself if it's old.
$itemsToDelete = $itemsToDelete | Where-Object { $_.FullName -ne $targetPath }
# Check if any items were found
if ($itemsToDelete.Count -gt 0) {
   Write-Host "`nFound $($itemsToDelete.Count) item(s) (files/directories) to delete:"
   $itemsToDelete | ForEach-Object {
       Write-Host "  - $($_.FullName) (Last Modified: $($_.LastWriteTime))"
   }
   Write-Host "`nProceeding with automatic deletion of items..."
   $itemsToDelete | ForEach-Object {
       try {
           # Use -Force and -Recurse for Remove-Item to handle both files and non-empty directories
           Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
           Write-Host "  - Deleted: $($_.FullName)" -ForegroundColor Green
       }
       catch {
           Write-Warning "  - Failed to delete $($_.FullName): $($_.Exception.Message)"
       }
   }
   Write-Host "`nCleanup complete."
} else {
   Write-Host "`nNo files or directories found older than $daysToKeep days in $targetPath."
}
