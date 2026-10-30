require "erb"

# The emails the app sends, in Portuguese. Each returns { subject:, html:, text: }.
module UserEmails
  module_function

  def verify(name, url)
    build("Confirme seu e-mail no Lixo Livre", name,
          "Falta só um passo para começar a reportar lixo no mapa: confirme que este e-mail é seu.",
          "Confirmar e-mail", url,
          "O link vale por 3 dias. Se você não criou uma conta no Lixo Livre, pode ignorar esta mensagem.")
  end

  def reset(name, url)
    build("Redefinir sua senha do Lixo Livre", name,
          "Recebemos um pedido para redefinir a senha da sua conta.",
          "Criar nova senha", url,
          "O link vale por 1 hora e só pode ser usado uma vez. Se não foi você, ignore esta mensagem: sua senha continua a mesma.")
  end

  def build(subject, name, intro, button, url, footer)
    greeting = "Olá, #{name}!"
    esc = ->(s) { ERB::Util.html_escape(s) }
    html = <<~HTML
      <div style="font-family:system-ui,Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#1d2a22">
        <h2 style="color:#1b7f3b;margin:0 0 16px">Lixo Livre</h2>
        <p>#{esc.(greeting)}</p>
        <p>#{esc.(intro)}</p>
        <p style="margin:24px 0"><a href="#{esc.(url)}" style="background:#1b7f3b;color:#fff;text-decoration:none;padding:12px 20px;border-radius:10px;font-weight:600;display:inline-block">#{esc.(button)}</a></p>
        <p style="color:#5f6b64;font-size:13px">Se o botão não funcionar, copie este endereço no navegador:<br>#{esc.(url)}</p>
        <p style="color:#5f6b64;font-size:13px">#{esc.(footer)}</p>
      </div>
    HTML
    text = "#{greeting}\n\n#{intro}\n\n#{button}: #{url}\n\n#{footer}\n"
    { subject: subject, html: html, text: text }
  end
end
