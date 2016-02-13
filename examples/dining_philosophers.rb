$: << File.join(File.dirname(__FILE__), '..', 'lib')
require 'petra'

def colored_string(string, color, format)
  "\e[#{Petra::Util::Debug::FORMATS[format]};#{Petra::Util::Debug::STRING_COLORS[color.to_sym]}m#{string}\e[0m"
end

class Philosopher
  attr_reader :number

  def initialize(number, *sticks)
    @number = number
    @left_stick, @right_stick = sticks
  end

  def eating?
    !!@eating
  end

  def think
    sleep(rand(5))
  end

  def take_stick(stick)
    fail Petra::Retry if stick.taken
    stick.taken = true
    stick.save
  end

  def put_stick(stick)
    stick.taken = false
    stick.save
  end

  def take_sticks
    Petra.transaction(identifier: "philosopher_#{@number}") do
      begin
        take_stick(@left_stick.petra)
        take_stick(@right_stick.petra)
        Petra.commit!
      rescue Petra::LockError => e
        # puts "#{Thread.current.name}: LockError(take) - #{e.message}"
        e.retry!
      rescue Petra::ReadIntegrityError, Petra::WriteClashError => e
        e.retry!
      end
    end
  end

  def put_sticks
    Petra.transaction(identifier: "philosopher_#{@number}") do
      put_stick(@left_stick.petra)
      put_stick(@right_stick.petra)
      Petra.commit!
    end
  end

  def eat
    take_sticks

    @eating = true
    sleep(2)
    @eating = false

    put_sticks
  end

  def live
    loop do
      think
      eat
    end
  end
end

class Stick < Mutex
  attr_reader :number

  def initialize(number)
    @number = number
  end

  alias_method :taken, :locked?

  def taken=(new_value)
    if new_value
      # puts "#{Thread.current.name} wants to take Stick ##{@number}"
      try_lock || fail(Exception, 'Already locked!')
    else
      # puts "#{Thread.current.name} wants to put Stick ##{@number} away"
      unlock
    end
  end

  def save
  end
end

Petra.configure do
  log_level :warn

  configure_class 'Stick' do
    proxy_instances true

    attribute_reader? do |method_name|
      %w(taken).include?(method_name.to_s)
    end

    attribute_writer? do |method_name|
      %w(taken=).include?(method_name.to_s)
    end

    persistence_method? do |method_name|
      %w(save).include?(method_name)
    end
  end
end

Thread::abort_on_exception = true

sticks = 5.times.map { |i| Stick.new(i) }
philosophers = 5.times.map { |i| Philosopher.new(i, sticks[i], sticks[(i + 1) % 5]) }

threads = philosophers.map do |phil|
  t = Thread.new { phil.live }
  t.name = "Philosopher #{phil.number}"
  t
end

loop do
  philosophers.each_with_index do |phil, idx|
    stick = sticks[idx]
    STDOUT.write stick.taken ? ' _ ' : ' | '
    STDOUT.write phil.eating? ? " 😁 " : " 😑 "
  end

  STDOUT.write("\r")
  # STDOUT.flush
  sleep(0.2)
end






