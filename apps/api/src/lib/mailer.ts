import { logger } from './logger';

export interface MailMessage {
  to: string;
  subject: string;
  text: string;
}

/**
 * Envio de e-mail. Nenhum provedor SMTP está configurado ainda: em desenvolvimento a mensagem
 * é registrada no log. Substitua a implementação ao integrar um provedor (SES, Resend, etc.).
 */
export const mailer = {
  sent: [] as MailMessage[],
  async send(message: MailMessage) {
    this.sent.push(message);
    if (this.sent.length > 50) this.sent.shift();
    logger.info({ to: message.to, subject: message.subject, text: message.text }, 'E-mail (transporte de log)');
  },
};
