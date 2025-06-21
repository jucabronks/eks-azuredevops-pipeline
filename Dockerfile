# =============================================================================
# DOCKERFILE - PROJETO VM APP
# =============================================================================

FROM node:18-alpine

# Diretório de trabalho
WORKDIR /app

# Copia arquivos de dependências
COPY package.json package-lock.json* ./

# Instala dependências
RUN npm install --production

# Copia o código da aplicação
COPY app.js ./

# Porta exposta
EXPOSE 3000

# Comando de inicialização
CMD ["node", "app.js"] 