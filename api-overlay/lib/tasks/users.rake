namespace :users do
  desc "Make an existing account an admin: bin/rails users:promote EMAIL=you@example.com [ROLE=moderator]"
  task promote: :environment do
    email = ENV.fetch("EMAIL") { abort "EMAIL=... is required" }
    role = ENV.fetch("ROLE", "admin")
    abort "ROLE must be one of #{User.roles.keys.join(', ')}" unless User.roles.key?(role)

    user = User.find_by(email: email.strip.downcase) or abort "No account with that email (sign up first)"
    user.update!(role: role)
    puts "#{user.email} is now #{user.role}"
  end
end
