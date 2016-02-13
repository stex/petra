module Petra
  module Util
    module Debug
      STRING_COLORS = {:light_gray => 90,
                       :yellow     => 33,
                       :green      => 32,
                       :red        => 31,
                       :purple     => 35,
                       :cyan       => 36,
                       :blue       => 34}

      FORMATS = {:default   => 0,
                 :bold      => 1,
                 :underline => 4}

      [:debug, :info, :warn, :error].each do |level|
        define_method level do |message, color = :light_gray, format = :default|
          log(message, level: level, color: color, format: format)
        end

        module_function level
      end

      def log(message, level: :debug, color: :light_gray, format: :default)
        logger.send(level, 'Petra :: ' << colored_string(message, color, format))
      end

      private

      def logger
        @logger ||= Logger.new(STDOUT).tap do |l|
          l.level = "Logger::#{Petra.configuration.log_level.upcase}".constantize
        end
      end

      def colored_string(string, color, format)
        "\e[#{Petra::Util::Debug::FORMATS[format]};#{Petra::Util::Debug::STRING_COLORS[color.to_sym]}m#{string}\e[0m"
      end

      module_function :log, :logger, :colored_string
    end
  end
end
