# Rails already keeps passwords, emails, tokens and secrets out of the logs. These carry credentials too:
# the Google ID token ("credential", also the passkey answer), and the two-factor and recovery codes ("code").
Rails.application.config.filter_parameters += %i[credential code recovery otp]
