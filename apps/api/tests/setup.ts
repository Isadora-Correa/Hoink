process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = process.env.TEST_DATABASE_URL ?? 'postgresql://hoink:hoink@localhost:5433/hoink_test';
process.env.APP_TIMEZONE = 'America/Sao_Paulo';
process.env.MARKET_DATA_SYNC = 'false';
process.env.ADMIN_TOKEN = 'admin-token-para-testes-123';
