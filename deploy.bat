@echo off
echo Copying master to all clients...
copy /Y "C:\landing-pages\quote\index.html" "C:\landing-pages\quote\test\index.html"
copy /Y "C:\landing-pages\quote\index.html" "C:\landing-pages\quote\kl-solar\index.html"
copy /Y "C:\landing-pages\quote\index.html" "C:\landing-pages\quote\mehala-energy\index.html"
copy /Y "C:\landing-pages\quote\index.html" "C:\landing-pages\quote\kaytechsolar\index.html"
echo Done copying!
echo.
echo Deploying to Vercel...
cd C:\landing-pages\quote
vercel --prod
echo.
echo Deploy complete!
