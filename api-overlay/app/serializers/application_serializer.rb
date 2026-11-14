# Turns a record into the JSON the pages and the mobile app receive. The API's shape lives here, not in
# the controllers (which decide *what* to send) and not in the models (which know nothing about JSON).
#
#   TrashSerializer.call(trash, urls: self)             one hash
#   TrashSerializer.collection(trashes, urls: self)     an array of hashes
#
# `urls` is whatever answers url_for (the controller): photo addresses are built with the request's host.
class ApplicationSerializer
  def self.call(record, **context)
    new(record, **context).as_json
  end

  def self.collection(records, **context)
    records.map { |record| call(record, **context) }
  end

  def initialize(record, **)
    @record = record
  end

  private

  attr_reader :record
end
