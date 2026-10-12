const express = require("express");
const cors = require("cors");
require("dotenv").config();

const authRoute = require("./route/authRoute");

const app = express();

app.use(cors());
app.use(express.json());

app.use("/api/auth", authRoute);


app.get("/", (req, res) => {
  res.send("ket noi thanh cong");
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`Server chạy tại http://localhost:${PORT}`);
});