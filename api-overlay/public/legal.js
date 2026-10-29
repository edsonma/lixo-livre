// Terms of Use and Privacy Policy shown in the app. Keep Terms::VERSION (app/models/terms.rb) in step:
// when the text changes in a way people must agree to again, change that date.
// who = { name, email } from /api/v1/status (LEGAL_NAME, LEGAL_EMAIL on the server).
window.LEGAL = function (who) {
  var name = (who && who.name) || "a equipe do Lixo Livre";
  var contact = (who && who.email) ? who.email : "o contato informado pela equipe do Lixo Livre";
  return {
    terms: {
      title: "Termos de Uso",
      sections: [
        ["O que é o Lixo Livre", "O Lixo Livre é um mapa colaborativo: pessoas fotografam lixo e entulho em espaços públicos, uma inteligência artificial (IA) estima o quanto o local está sujo, e o resultado aparece num mapa de calor que ajuda a cidade a ver onde agir."],
        ["Sua conta", "Para enviar fotos você precisa de uma conta, ter 18 anos ou mais (ou autorização de um responsável) e informar dados verdadeiros. Sua senha, sua biometria e o acesso ao seu aparelho são pessoais: você responde pelo que for feito com a sua conta."],
        ["Suas fotos", "Fotografe somente lixo em locais públicos ou com permissão de quem os controla. Não fotografe pessoas de propósito, não entre em propriedades privadas e não se arrisque para tirar uma foto. Você declara que a foto é sua e nos autoriza, sem custo e de forma não exclusiva, a exibi-la no mapa e nas telas do aplicativo enquanto ela estiver publicada."],
        ["O que não é permitido", "Enviar fotos falsas ou de outro lugar, repetir a mesma foto para inflar a nota, enviar conteúdo ilegal, ofensivo ou que mostre pessoas identificáveis, ou tentar burlar a moderação. Podemos recusar, esconder ou remover fotos e suspender contas que descumprirem estes termos."],
        ["A nota da IA", "A nota de 0 a 100 é uma estimativa automática e pode errar. Ela não é laudo, vistoria nem denúncia oficial, e não substitui os canais da prefeitura ou dos órgãos de limpeza urbana."],
        ["Sem garantias", "O serviço é oferecido como está, pode mudar ou ficar indisponível, e não garantimos que o mapa esteja completo ou atualizado. Não nos responsabilizamos por decisões tomadas apenas com base nele."],
        ["Encerrar a conta", "Você pode excluir sua conta a qualquer momento em Perfil, “Excluir minha conta”. As suas fotos saem do mapa e os locais são recalculados."],
        ["Mudanças", "Se estes termos mudarem de forma relevante, pediremos um novo aceite antes do seu próximo envio de foto."],
        ["Lei e contato", "Estes termos seguem a lei brasileira. Dúvidas: " + contact + ". Responsável: " + name + "."]
      ]
    },
    privacy: {
      title: "Política de Privacidade",
      sections: [
        ["Quem cuida dos seus dados", name + " é a responsável (controladora) pelos dados tratados no Lixo Livre, conforme a Lei Geral de Proteção de Dados (LGPD). Contato para qualquer pedido sobre dados: " + contact + "."],
        ["Que dados coletamos", "Conta: nome, e-mail e senha (guardada de forma criptografada), ou o identificador da sua conta Google. Biometria: se você ativar, guardamos apenas a chave pública do seu aparelho; sua digital ou seu rosto nunca saem do aparelho. Fotos: a imagem, o local (GPS) e a data e hora em que foi tirada, e dados técnicos da câmera quando presentes. Uso: um identificador anônimo do aparelho e registros de segurança."],
        ["Para que usamos", "Para criar sua conta, receber e analisar suas fotos, montar o mapa de calor, mostrar o histórico dos locais, avisar sobre locais que você segue, moderar conteúdo e evitar fraudes e abusos. Tratamos os dados com base no seu consentimento, na execução do serviço que você pediu e no nosso interesse legítimo de segurança."],
        ["Rostos e placas", "Antes de publicar, detectamos rostos e placas de veículos e os cobrimos com um mosaico. Se não conseguimos proteger a foto, ela fica privada para revisão humana. Nenhum método é perfeito: se você achar uma foto com pessoa ou placa visível, use “Denunciar” ou escreva para nós e removeremos."],
        ["O que fica público", "No mapa aparecem a foto já protegida, a nota, os tipos de lixo, a data, o local onde a foto foi tirada e o nome da sua conta. Seu e-mail nunca é exibido."],
        ["Com quem compartilhamos", "Não vendemos seus dados. Usamos prestadores que tratam dados em nosso nome: provedor de inteligência artificial (a Anthropic, nos Estados Unidos) que recebe a imagem para detectar rostos e placas (sem dados de localização) e para avaliar o lixo (já com o mosaico); hospedagem e armazenamento de arquivos; e o Google, se você entrar com a conta Google. Isso pode envolver transferência internacional de dados, com os cuidados exigidos pela LGPD."],
        ["Cookies", "Usamos apenas um cookie essencial para manter você conectado. Não usamos cookies de publicidade nem de rastreamento."],
        ["Por quanto tempo guardamos", "Enquanto sua conta existir. A foto original é substituída pela versão protegida. Se você excluir a conta, apagamos suas fotos e seus dados de conta, salvo o que a lei nos obrigar a guardar."],
        ["Seus direitos", "Você pode pedir confirmação de que tratamos seus dados, acesso, correção, anonimização, portabilidade, eliminação, informação sobre com quem compartilhamos e revogar o consentimento. Você mesmo exclui a conta em Perfil; para os demais pedidos escreva para " + contact + ". Também pode reclamar à Autoridade Nacional de Proteção de Dados (ANPD)."],
        ["Crianças e adolescentes", "O serviço é para maiores de 18 anos. Menores só podem usar com autorização de um responsável."],
        ["Segurança e mudanças", "Usamos conexão criptografada, senhas protegidas e acesso restrito ao painel de moderação. Se esta política mudar de forma relevante, pediremos um novo aceite."]
      ]
    }
  };
};
