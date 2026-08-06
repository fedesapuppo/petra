module EnvFile
  def self.load(path = File.expand_path("../.env", __dir__))
    return unless File.exist?(path)

    File.readlines(path).each do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")

      key, _, value = line.partition("=")
      ENV[key.strip] ||= value.strip
    end
  end
end
