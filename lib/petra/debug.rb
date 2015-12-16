module Petra
  module Debug
    STRING_COLORS = {:light_gray => 90,
                     :yellow     => 33,
                     :green      => 32,
                     :red        => 31}

    def self.log(message, color = :light_gray)
      $stdout.puts 'Petra :: ' << colored_string(message, color)
    end

    private

    def self.colored_string(string, color)
      "\e[#{STRING_COLORS[color.to_sym]}m#{string}\e[0m"
    end
  end
end
