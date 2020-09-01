module RSpecQ
  class Reporter
    def initialize(build_id:, timeout:, redis_opts:)
      @build_id = build_id
      @timeout = timeout
      @queue = Queue.new(build_id, "reporter", redis_opts)

      # We want feedback to be immediattely printed to CI users, so
      # we disable buffering.
      STDOUT.sync = true
    end

    def report
      @queue.wait_until_published

      finished = false

      reported_failures = {}
      failure_heading_printed = false

      tests_duration = measure_duration do
        @timeout.times do |i|
          @queue.example_failures.each do |job, rspec_output|
            next if reported_failures[job]

            if !failure_heading_printed
              puts "\nFailures:\n"
              failure_heading_printed = true
            end

            reported_failures[job] = true
            puts failure_formatted(rspec_output)
          end

          if !@queue.exhausted?
            sleep 1
            next
          end

          finished = true
          break
        end
      end

      raise "Build not finished after #{@timeout} seconds" if !finished

      @queue.record_build_time(tests_duration)
      puts summary(@queue.example_failures, @queue.non_example_errors,
                   humanize_duration(tests_duration))

      exit 1 if !@queue.build_successful?
    end

    private

    def measure_duration
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).round(2)
    end

    # We try to keep this output consistent with RSpec's original output
    def summary(failures, errors, duration)
      failed_examples_section = "\nFailed examples:\n\n"

      failures.each do |_job, msg|
        parts = msg.split("\n")
        failed_examples_section << "  #{parts[-1]}\n"
      end

      summary = ""
      summary << failed_examples_section if !failures.empty?

      errors.each { |_job, msg| summary << msg }

      summary << "\n"
      summary << "Total results:\n"
      summary << "  #{@queue.example_count} examples "     \
                 "(#{@queue.processed_jobs_count} jobs), " \
                 "#{failures.count} failures, "            \
                 "#{errors.count} errors"
      summary << "\n\n"
      summary << "Spec execution time: #{duration}"
    end

    def failure_formatted(rspec_output)
      rspec_output.split("\n")[0..-2].join("\n")
    end

    def humanize_duration(seconds)
      Time.at(seconds).utc.strftime("%H:%M:%S")
    end
  end
end
