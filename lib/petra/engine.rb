module Petra
  class Engine < ::Rails::Engine
    isolate_namespace Petra
    config.autoload_paths += Gem.loaded_specs['petra'].load_paths
    config.watchable_dirs[root.join('lib').to_s] = [:rb]
  end
end
