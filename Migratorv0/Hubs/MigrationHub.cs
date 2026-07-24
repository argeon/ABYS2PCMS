using Microsoft.AspNetCore.SignalR;
using MigrationShared.Models;
using MigrationWeb.Services;

namespace MigrationWeb.Hubs;

public class MigrationHub : Hub
{
    private readonly DashboardDataService _dataService;
    private readonly ILogger<MigrationHub> _logger;

    public MigrationHub(DashboardDataService dataService, ILogger<MigrationHub> logger)
    {
        _dataService = dataService;
        _logger = logger;
    }

    public async Task<MigrationSummary?> GetCurrentSummary()
    {
        try
        {
            return await _dataService.GetCurrentSummary();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting current summary");
            return null;
        }
    }

    public async Task<List<TableStatus>> GetTableStatuses()
    {
        try
        {
            return await _dataService.GetTableStatuses();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting table statuses");
            return new List<TableStatus>();
        }
    }

    public async Task<List<PartitionStatus>> GetPartitionStatuses()
    {
        try
        {
            return await _dataService.GetPartitionStatuses();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting partition statuses");
            return new List<PartitionStatus>();
        }
    }

    public async Task<List<ProgressEvent>> GetRecentEvents(int limit = 100)
    {
        try
        {
            return await _dataService.GetRecentEvents(limit);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting recent events");
            return new List<ProgressEvent>();
        }
    }

    public override async Task OnConnectedAsync()
    {
        _logger.LogInformation("Client connected: {ConnectionId}", Context.ConnectionId);
        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        _logger.LogInformation("Client disconnected: {ConnectionId}", Context.ConnectionId);
        await base.OnDisconnectedAsync(exception);
    }
}
