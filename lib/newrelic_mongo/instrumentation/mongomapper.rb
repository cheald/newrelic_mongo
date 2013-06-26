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
      # Slight override to Newrelic's tracing method definition. This allows us to include
      # the model name in reporting of the traced code. :)
      class << self
        def method_with_push_scope_with_model_hack(method_name, metric_name_code, options)
          method_with_push_scope_without_model_hack(method_name, metric_name_code, options).gsub(
            /trace_execution_scoped\(\"(.*?)\"/m, 'trace_execution_scoped("\\1" % model.class'
          )
        end
        alias_method_chain :method_with_push_scope, :model_hack
      end

      ::Plucky::Methods.each do |method|
        add_method_tracer method, "Database/Mongo/%%s/#{method}"
      end
    end
  end
end
