# Runs the same photos through several providers and lays the answers side by side, so you can pick
# the one that agrees with your own judgment. Used by `bin/rails vision:compare`.
#
#   TrashVision::Comparison.new(providers: { "claude" => adapter, "gemini" => adapter }).run(paths)
#
# A provider that fails on a photo shows the error in its cell instead of stopping the run.
class TrashVision
  class Comparison
    CONTENT_TYPES = { ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".png" => "image/png", ".webp" => "image/webp" }.freeze
    Cell = Struct.new(:severity, :types, :confidence, :seconds, :error, keyword_init: true)

    def initialize(providers:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @providers = providers
      @clock = clock
    end

    # { "photo.jpg" => { "claude" => Cell, "gemini" => Cell } }
    def run(paths)
      paths.to_h do |path|
        image = TrashVision::Image.new(bytes: File.binread(path), content_type: content_type(path))
        [File.basename(path), @providers.to_h { |name, adapter| [name, ask(adapter, image)] }]
      end
    end

    def self.table(results)
      names = results.values.flat_map(&:keys).uniq
      rows = [["photo", *names]]
      results.each { |photo, cells| rows << [photo, *names.map { |name| describe(cells[name]) }] }
      widths = rows.transpose.map { |column| column.map(&:length).max }
      rows.map { |row| row.each_with_index.map { |text, i| text.ljust(widths[i]) }.join("  ").rstrip }.join("\n")
    end

    def self.describe(cell)
      return "-" if cell.nil?
      return "ERROR #{cell.error}"[0, 70] if cell.error
      return "not trash (#{cell.confidence}, #{cell.seconds}s)" if cell.severity.nil?

      "#{cell.severity} #{cell.types.join('+')} (#{cell.confidence}, #{cell.seconds}s)"
    end

    private

    def ask(adapter, image)
      started = @clock.call
      result = TrashVision.normalize(adapter.call(image))
      Cell.new(severity: result.severity, types: result.types, confidence: result.confidence.round(2), seconds: (@clock.call - started).round(1))
    rescue StandardError => e
      Cell.new(error: "#{e.class.name.split('::').last}: #{e.message}")
    end

    def content_type(path)
      CONTENT_TYPES.fetch(File.extname(path).downcase) { raise ArgumentError, "unsupported photo type: #{path}" }
    end
  end
end
