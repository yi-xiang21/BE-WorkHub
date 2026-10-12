const crypto = require("crypto");
const jwt = require("jsonwebtoken");
const authRepository = require("../repositorys/authRepository");

class AuthService {
  hashPassword(password) {
    return crypto.createHash("sha256").update(password).digest("hex");
  }

  validateEmailAndPassword(email, password) {
    if (!email || !password) {
      throw new Error("Email and password are required");
    }

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      throw new Error("Email is invalid");
    }

    if (password.length < 6) {
      throw new Error("Password must be at least 6 characters");
    }
  }

  getJwtConfig() {
    const accessTokenSecret = process.env.ACCESS_TOKEN_SECRET;
    const refreshTokenSecret = process.env.REFRESH_TOKEN_SECRET;

    if (!accessTokenSecret || !refreshTokenSecret) {
      throw new Error("ACCESS_TOKEN_SECRET and REFRESH_TOKEN_SECRET are required");
    }

    return {
      accessTokenSecret,
      refreshTokenSecret,
      accessTokenExpiresIn: process.env.ACCESS_TOKEN_EXPIRES_IN || "15m",
      refreshTokenExpiresIn: process.env.REFRESH_TOKEN_EXPIRES_IN || "7d",
    };
  }

  hashToken(token) {
    return crypto.createHash("sha256").update(token).digest("hex");
  }

  getExpiresAtFromToken(token) {
    const decoded = jwt.decode(token);
    if (!decoded || !decoded.exp) {
      throw new Error("Invalid refresh token");
    }

    return new Date(decoded.exp * 1000);
  }

  createTokenPayload(user) {
    return {
      id: user.id,
      email: user.email,
    };
  }

  createAccessToken(user, config) {
    const payload = this.createTokenPayload(user);
    return jwt.sign(payload, config.accessTokenSecret, {
      expiresIn: config.accessTokenExpiresIn,
    });
  }

  createRefreshToken(user, config) {
    const payload = {
      ...this.createTokenPayload(user),
      tokenType: "refresh",
      nonce: crypto.randomBytes(16).toString("hex"),
    };

    return jwt.sign(payload, config.refreshTokenSecret, {
      expiresIn: config.refreshTokenExpiresIn,
    });
  }

  async issueTokens(user) {
    const config = this.getJwtConfig();
    const accessToken = this.createAccessToken(user, config);
    const refreshToken = this.createRefreshToken(user, config);

    const refreshTokenHash = this.hashToken(refreshToken);
    const refreshTokenExpiresAt = this.getExpiresAtFromToken(refreshToken);

    await authRepository.saveRefreshToken(
      user.id,
      refreshTokenHash,
      refreshTokenExpiresAt,
    );

    return {
      accessToken,
      refreshToken,
    };
  }

  async login(email, password) {
    this.validateEmailAndPassword(email, password);

    const passwordHash = this.hashPassword(password);
    const user = await authRepository.login(email, passwordHash);

    if (!user) {
      throw new Error("Invalid email or password");
    }

    const tokens = await this.issueTokens(user);
    return {
      user,
      ...tokens,
    };
  }

  async register(name, email, password) {
    if (!name || name.trim().length < 2) {
      throw new Error("Full name must be at least 2 characters ");
    }

    this.validateEmailAndPassword(email, password);

    const existingUser = await authRepository.findByEmail(email);
    if (existingUser) {
      throw new Error("Email already exists");
    }

    const passwordHash = this.hashPassword(password);
    const user = await authRepository.register(name.trim(), email, passwordHash);

    if (!user) {
      throw new Error("Registration failed");
    }

    const tokens = await this.issueTokens(user);
    return {
      "id": user.id,
      "name": user.name,
      ...tokens,
    };
  }

  async refreshToken(refreshToken) {
    if (!refreshToken) {
      throw new Error("Refresh token is required");
    }

    const config = this.getJwtConfig();

    let payload;
    try {
      payload = jwt.verify(refreshToken, config.refreshTokenSecret);
    } catch (error) {
      throw new Error("Refresh token is invalid or expired");
    }

    const tokenHash = this.hashToken(refreshToken);
    const tokenRecord = await authRepository.findValidRefreshToken(
      payload.id,
      tokenHash,
    );

    if (!tokenRecord) {
      throw new Error("Refresh token is invalid or revoked");
    }

    const user = await authRepository.findById(payload.id);
    if (!user) {
      throw new Error("User not found");
    }

    await authRepository.revokeRefreshTokenByHash(tokenHash);

    const tokens = await this.issueTokens(user);
    return {
      user,
      ...tokens,
    };
  }

  async logout(refreshToken) {
    if (!refreshToken) {
      throw new Error("Refresh token is required");
    }

    const tokenHash = this.hashToken(refreshToken);
    await authRepository.revokeRefreshTokenByHash(tokenHash);

    return { message: "Logged out successfully" };
  }
}

module.exports = new AuthService();
