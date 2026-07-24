using Microsoft.AspNetCore.SignalR;
using MigrationWeb.Hubs;

namespace MigrationWeb.Services;

public class CheckpointPollingService : BackgroundService
{
    private readonly DashboardDataService _dataService;
    private readonly IHubContext<MigrationHub> _hubContext;
    private readonly ILogger<CheckpointPollingService> _logger;

    public CheckpointPollingService(
        DashboardDataService dataService,
        IHubContext<MigrationHub> hubContext,
        ILogger<CheckpointPollingService> logger)
    {
        _dataService = dataService;
        _hubContext = hubContext;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("CheckpointPollingService started");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var summary = await _dataService.GetCurrentSummary();
                if (summary != null)
                {
                    await _hubContext.Clients.All.SendAsync("UpdateSummary", summary, stoppingToken);
                }

                var partitions = await _dataService.GetPartitionStatuses();
                await _hubContext.Clients.All.SendAsync("UpdatePartitions", partitions, stoppingToken);

                var events = await _dataService.GetRecentEvents(80);
                await _hubContext.Clients.All.SendAsync("UpdateEvents", events, stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in CheckpointPollingService");
            }

            await Task.Delay(2000, stoppingToken); // 2 saniye canlı izleme
        }

        _logger.LogInformation("CheckpointPollingService stopped");
    }
}
