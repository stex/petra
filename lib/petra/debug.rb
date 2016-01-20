module Petra
  module Debug
    STRING_COLORS = {:light_gray => 90,
                     :yellow     => 33,
                     :green      => 32,
                     :red        => 31}

    [:debug, :info, :warn, :error].each do |level|
      define_method level do |message, color = :light_gray|
        log(message, level: level, color: color)
      end

      module_function level
    end

    def log(message, level: :debug, color: :light_gray)
      logger.send(level, 'Petra :: ' << colored_string(message, color))
    end

    private

    def logger
      @logger ||= Logger.new(STDOUT).tap do |l|
        l.level = "Logger::#{Petra.configuration.log_level.upcase}".constantize
      end
    end

    def colored_string(string, color)
      "\e[#{STRING_COLORS[color.to_sym]}m#{string}\e[0m"
    end

    module_function :log, :logger, :colored_string
  end
end
