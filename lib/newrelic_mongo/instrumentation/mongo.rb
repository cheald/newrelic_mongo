# Mongo Instrumentation originally contributed by Alexey Palazhchenko
DependencyDetection.defer do
  @name = :mongodb

  depends_on do
    defined?(::Mongo) and not NewRelic::Control.instance['disable_mongodb']
  end

  executes do
    NewRelic::Agent.logger.info 'Installing mongo-ruby-driver instrumentation'
  end

  executes do
    ::Mongo::Logging.class_eval do
      include NewRelic::Agent::MethodTracer

      def instrument_with_newrelic_trace(name, payload = {}, &blk)
        payload = {} if payload.nil?
        collection = payload[:collection]
        if collection == '$cmd'
          instrument_without_newrelic_trace(name, payload, &blk)
        else
          trace_execution_scoped("Database/#{collection}/#{name}") do
            t0 = Time.now
            res = instrument_without_newrelic_trace(name, payload, &blk)
            NewRelic::Agent.instance.transaction_sampler.notice_sql(payload.inspect, nil, (Time.now - t0).to_f)
            res
          end
        end
      end

      alias_method :instrument_without_newrelic_trace, :instrument
      alias_method :instrument, :instrument_with_newrelic_trace
    end
    class Mongo::Collection; include Mongo::Logging; end
    class Mongo::Connection; include Mongo::Logging; end
    class Mongo::Cursor; include Mongo::Logging; end

    # cursor refresh is not currently instrumented in mongo driver, so not picked up by above - have to add our own here
    ::Mongo::Cursor.class_eval do
      include NewRelic::Agent::MethodTracer

      def send_get_more_with_newrelic_trace
        trace_execution_scoped("Database/#{collection.name}/refresh") do
          send_get_more_without_newrelic_trace
        end
      end
      alias_method :send_get_more_without_newrelic_trace, :send_get_more
      alias_method :send_get_more, :send_get_more_with_newrelic_trace
      add_method_tracer :close, 'Database/#{collection.name}/close'
    end
  end

end
