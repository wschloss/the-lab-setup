const http = require('http');

const server = http.createServer((request, response) => {
  response.writeHead(200, {"Content-Type": "text/html"});
  response.end("<h1>This site is currently under construction</h1>");
});

server.listen(8080);
console.log("Server running on 8080");
