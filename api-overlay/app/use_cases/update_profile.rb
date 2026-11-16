# The person edits their own profile: full name, bio, website, gender and picture. These are the ONLY things
# it can change. The email is the login and is never touched here, and neither is the role or anything else.
#
# `fields` holds only the keys the person sent (a key that is missing is left alone; a blank one clears
# the field, except the name, which cannot be blank). `avatar` is an uploaded file or nil; `remove_avatar`
# deletes the current picture. Everything is checked first, so a bad bio never leaves a half-saved profile.
# Raises ActiveRecord::RecordInvalid (the controller answers 422 with the messages per field).
class UpdateProfile
  EDITABLE = %i[name bio website gender].freeze

  def self.call(...)
    new(...).call
  end

  def initialize(user:, fields: {}, avatar: nil, remove_avatar: false)
    @user = user
    @fields = fields.to_h.symbolize_keys.slice(*EDITABLE)
    @upload = avatar
    @remove_avatar = remove_avatar
  end

  def call
    @user.assign_attributes(@fields)
    @user.validate
    @user.errors.add(:name, :blank) if @fields.key?(:name) && @fields[:name].to_s.strip.empty?
    jpeg = process_upload
    raise ActiveRecord::RecordInvalid, @user if @user.errors.any?

    User.transaction do
      @user.save!
      if jpeg
        @user.avatar.attach(io: StringIO.new(jpeg), filename: "avatar.jpg", content_type: "image/jpeg") # the old one is purged in the background
      elsif @remove_avatar
        @user.avatar.purge_later
      end
    end
    @user
  end

  private

  def process_upload
    return unless @upload.respond_to?(:read)

    if @upload.respond_to?(:size) && @upload.size.to_i > Photos::Avatar::MAX_UPLOAD_BYTES
      @user.errors.add(:avatar, "is too large")
      return
    end
    Photos::Avatar.call(@upload.read)
  rescue Photos::Avatar::Invalid
    @user.errors.add(:avatar, "is not a usable image")
    nil
  end
end
