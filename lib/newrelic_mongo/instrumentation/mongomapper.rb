DependencyDetection.defer do
  @name = :plucky

  depends_on do
    defined?(::Plucky::Query) &&
    !NewRelic::Control.instance['disable_mongomapper']
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Mongomapper instrumentation'

    class Plucky::Query
      include NewRelic::Agent::MethodTracer

      def command_with_newrelic(command, *args)
        if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
          total_metric = 'Database/Mongo/allWeb'
        else
          total_metric = 'Database/Mongo/allOther'
        end

        metrics = ["Database/Mongo/#{model}\##{command.to_s}", total_metric]

        self.class.trace_execution_scoped(metrics) do
          start = Time.now
          begin
            send("#{command}_without_newrelic", *args)
          ensure
            s = NewRelic::Agent.instance.transaction_sampler
            s.notice_nosql(args.inspect, (Time.now - start).to_f) rescue nil
          end
        end
      end

      %w(find_one find all last remove count distinct update cursor).each do |method|
        define_method("#{method}_with_newrelic") do |*args|
          command_with_newrelic(method, *args)
        end
        alias_method_chain method, :newrelic
      end
    end
  end
end
