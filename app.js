const express = require('express');
const app = express();
const port = 3000;

const PROJECT_NAME = process.env.PROJECT_NAME || 'projeto-vm';
const ENVIRONMENT = process.env.ENVIRONMENT || 'dev';
const INSTANCE_ID = process.env.INSTANCE_ID || 'local';
const REGION = process.env.REGION || 'local';

app.get('/', (req, res) => {
    res.json({
        message: `Hello from ${PROJECT_NAME}-${ENVIRONMENT}`,
        instance_id: INSTANCE_ID,
        region: REGION,
        timestamp: new Date().toISOString()
    });
});

app.get('/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.get('/metadata', (req, res) => {
    res.json({
        instance_id: INSTANCE_ID,
        region: REGION,
        project: PROJECT_NAME,
        environment: ENVIRONMENT
    });
});

app.listen(port, () => {
    console.log(`App listening at http://localhost:${port}`);
}); 