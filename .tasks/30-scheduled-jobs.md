# Scheduled Jobs / Cron

## Status
Open — no scheduler, cron parser, timezone support, missed execution handling, or execution history implementation found.

## Problem
Some tasks need to run on a schedule, not in response to events. No built-in cron-like functionality.

## Goal
Add scheduled job support with cron expressions and one-time scheduling.

## Tasks

### 1. Cron Jobs
```ruby
class DailyReportJob < LePain::ScheduledJob
  cron '0 9 * * *'  # every day at 9 AM

  def self.execute
    ReportService.generate_daily
  end
end
```

### 2. One-Time Scheduling
```ruby
LePain::Scheduler.schedule_at(
  job: CleanupJob,
  at: Time.now + 3600,
  payload: { older_than: 30.days.ago },
)
```

### 3. Scheduler Engine
- [ ] Cron expression parser
- [ ] Timezone support
- [ ] Missed execution handling
- [ ] Concurrent execution prevention

### 4. Monitoring
- [ ] Next execution time
- [ ] Last execution result
- [ ] Missed executions alert
- [ ] Execution history

### 5. Config Support
```yaml
scheduler:
  enabled: true
  timezone: UTC
  max_concurrent: 5
  missed_execution: skip  # skip, run_now, run_all
```

## Acceptance Criteria
- Cron jobs execute on schedule
- Timezone is respected
- Missed executions are handled correctly
- Scheduler state persists across restarts
