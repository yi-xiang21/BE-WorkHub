const pool = require("../config/db");

class AuthRepository {
    async findByEmail(email) {
        const query = "SELECT id, name, email FROM users WHERE email = $1";
        const values = [email];

        const result = await pool.query(query, values);
        return result.rows[0] || null;
    }

    async findById(userId) {
        const query = `
            SELECT id, name, email, created_at
            FROM users
            WHERE id = $1
        `;
        const values = [userId];

        const result = await pool.query(query, values);
        return result.rows[0] || null;
    }

    async login(email, passwordHash) {
        const query = `
            SELECT id, name, email, created_at
            FROM users
            WHERE email = $1 AND password_hash = $2
        `;
        const values = [email, passwordHash];

        const result = await pool.query(query, values);
        return result.rows[0] || null;
    }

    async register(name, email, passwordHash) {
        const query = `
            INSERT INTO users (name, email, password_hash)
            VALUES ($1, $2, $3)
            RETURNING id, name, email, created_at
        `;
        const values = [name, email, passwordHash];

        const result = await pool.query(query, values);
        return result.rows[0] || null;
    }

    async saveRefreshToken(userId, tokenHash, expiresAt) {
        const query = `
            INSERT INTO refresh_tokens (token_hash, user_id, expires_at)
            VALUES ($1, $2, $3)
            RETURNING id, token_hash, expires_at
        `;
        const values = [tokenHash, userId, expiresAt];

        const result = await pool.query(query, values);
        return result.rows[0] || null;
    }

    async findValidRefreshToken(userId, tokenHash) {
        const query = `
            SELECT id, token_hash, expires_at, revoked_at
            FROM refresh_tokens
            WHERE user_id = $1
                AND token_hash = $2
                AND revoked_at IS NULL
                AND expires_at > NOW()
            LIMIT 1
        `;
        const values = [userId, tokenHash];

        const result = await pool.query(query, values);
        return result.rows[0] || null;
    }

    async revokeRefreshTokenByHash(tokenHash) {
        const query = `
            UPDATE refresh_tokens
            SET revoked_at = NOW()
            WHERE token_hash = $1 AND revoked_at IS NULL
        `;
        const values = [tokenHash];

        await pool.query(query, values);
    }
}

module.exports = new AuthRepository();