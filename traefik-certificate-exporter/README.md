# Traefik Certificate Extractor

Forked from [DanielHuisman/traefik-certificate-extractor](https://github.com/DanielHuisman/traefik-certificate-extractor)

Tool to extract Let's Encrypt certificates from Traefik's ACME storage file. Can automatically restart containers using the docker API.

## Output
```
/ssl/
    example.com.crt
    example.com.key
    example.com.chain.pem
    sub.example.nl.crt
    sub.example.nl.key
    sub.example.nl.chain.pem
```
