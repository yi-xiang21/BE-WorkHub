const authService = require("../services/authService");
const cookie = require("cookie");

function mapAuthErrorStatus(message) {
    if (!message) {
        return 400;
    }

    if (message.includes("already exists")) {
        return 409;
    }

    if (
        message.includes("invalid") ||
        message.includes("expired") ||
        message.includes("revoked") ||
        message.includes("not found")
    ) {
        return 401;
    }

    return 400;
}

async function registerUser(req, res) {
    try {
        const { name, email, password } = req.body;
        const user = await authService.register(name, email, password);
        res.cookie("refreshToken", user.refreshToken, {
            httpOnly: true,
            secure: true,
            sameSite: "strict",
            maxAge: 7 * 24 * 60 * 60 * 1000,
        });
        res.status(201).json(user);
    } catch (error) {
        res.status(mapAuthErrorStatus(error.message)).json({ message: error.message });
    }
}

async function loginUser(req, res) {
    try {
        const { email, password } = req.body;
        const user = await authService.login(email, password);
        res.cookie("refreshToken", user.refreshToken, {
            httpOnly: true,
            secure: true,
            sameSite: "strict",
            maxAge: 7 * 24 * 60 * 60 * 1000,
        });
        res.status(200).json(user);
    } catch (error) {
        res.status(mapAuthErrorStatus(error.message)).json({ message: error.message });
    }
}

async function refreshToken(req, res) {
    try {
        const cookies = req.headers.cookie ? cookie.parse(req.headers.cookie) : {};
        const token = cookies.refreshToken || req.body.refreshToken;
        const data = await authService.refreshToken(token);
        res.status(200).json(data);
    } catch (error) {
        res.status(mapAuthErrorStatus(error.message)).json({ message: error.message });
    }
}

async function logoutUser(req, res) {
    try {
        const cookies = req.headers.cookie ? cookie.parse(req.headers.cookie) : {};
        const token = cookies.refreshToken || req.body.refreshToken;
        const data = await authService.logout(token);
        res.status(200).json(data);
    } catch (error) {
        res.status(mapAuthErrorStatus(error.message)).json({ message: error.message });
    }
}

module.exports = {
    registerUser,
    loginUser,
    refreshToken,
    logoutUser,
};

