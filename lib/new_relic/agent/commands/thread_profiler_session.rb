# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/threading/agent_thread'
require 'new_relic/agent/threading/backtrace_service'
require 'new_relic/agent/threading/thread_profile'

module NewRelic
  module Agent
    module Commands

      class ThreadProfilerSession

        def initialize(backtrace_service)
          @backtrace_service = backtrace_service
          @started_at = nil
          @finished_profile = nil
        end

        def handle_start_command(agent_command)
          raise_unsupported_error unless NewRelic::Agent::Threading::BacktraceService.is_supported?
          raise_thread_profiler_disabled unless enabled?
          raise_already_started_error if running?
          start(agent_command)
        end

        def handle_stop_command(agent_command)
          report_data = agent_command.arguments.fetch("report_data", true)
          stop(report_data)
        end

        def start(agent_command)
          NewRelic::Agent.logger.debug("Starting Thread Profiler.")
          profile = @backtrace_service.subscribe(
            NewRelic::Agent::Threading::BacktraceService::ALL_TRANSACTIONS,
            agent_command.arguments
          )

          @started_at = Time.now
          @duration = profile.duration if profile
        end

        def stop(report_data)
          return unless running?
          NewRelic::Agent.logger.debug("Stopping Thread Profiler.")
          @finished_profile = @backtrace_service.harvest(NewRelic::Agent::Threading::BacktraceService::ALL_TRANSACTIONS)
          @backtrace_service.unsubscribe(NewRelic::Agent::Threading::BacktraceService::ALL_TRANSACTIONS)
          @finished_profile = nil if !report_data
        end

        def harvest
          NewRelic::Agent.logger.debug("Harvesting from Thread Profiler #{@finished_profile.to_log_description unless @finished_profile.nil?}")
          profile = @finished_profile
          @backtrace_service.profile_agent_code = false
          @finished_profile = nil
          @started_at = nil
          profile
        end

        def enabled?
          NewRelic::Agent.config[:'thread_profiler.enabled']
        end

        def running?
          @backtrace_service.subscribed?(NewRelic::Agent::Threading::BacktraceService::ALL_TRANSACTIONS)
        end

        def ready_to_harvest?
          past_time? || stopped?
        end

        def past_time?
          @started_at && (Time.now > @started_at + @duration)
        end

        def stopped?
          !!@finished_profile
        end

        private

        def raise_command_error(msg)
          raise NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError.new(msg)
        end

        def raise_unsupported_error
          msg = <<-EOF
Thread profiling is only supported on 1.9.2 and greater versions of Ruby.
We detected running agents capable of profiling, but the profile started with
an agent running Ruby #{RUBY_VERSION}.

Profiling again might select an appropriate agent, but we recommend running a
consistent version of Ruby across your application for better results.
          EOF
          raise_command_error(msg)
        end

        def raise_thread_profiler_disabled
          msg = "Not starting Thread Profiler because of config 'thread_profiler.enabled' = #{enabled?}"
          raise_command_error(msg)
        end

        def raise_already_started_error
          msg = "Profile already in progress. Ignoring agent command to start another."
          raise_command_error(msg)
        end

      end
    end
  end
end
