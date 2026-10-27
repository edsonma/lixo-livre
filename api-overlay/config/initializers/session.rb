# The app is API-only, which drops the cookie/session middleware. Login needs a session, so it is put
# back: an encrypted, HttpOnly, SameSite=Lax cookie (Lax means other sites cannot make the browser
# send it on a POST; BaseController also refuses cross-origin writes by their Origin header).
Rails.application.config.middleware.use ActionDispatch::Cookies
Rails.application.config.middleware.use ActionDispatch::Session::CookieStore,
                                        key: "_lixo_livre_session",
                                        same_site: :lax,
                                        secure: Rails.env.production?,
                                        httponly: true,
                                        expire_after: 30.days
