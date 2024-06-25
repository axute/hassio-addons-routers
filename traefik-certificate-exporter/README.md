# Traefik Certificate Extractor

Forked from [DanielHuisman/traefik-certificate-extractor](https://github.com/DanielHuisman/traefik-certificate-extractor)

Tool to extract Let's Encrypt certificates from Traefik's ACME storage file. Can automatically restart containers using the docker API.

## Output
```
/ssl/
    example.com/
        cert.pem
        chain.pem
        fullchain.pem
        privkey.pem
    sub.example.nl/
        cert.pem
        chain.pem
        fullchain.pem
        privkey.pem
```
