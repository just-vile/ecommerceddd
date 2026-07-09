# See https://aka.ms/customizecontainer to learn how to customize your debug container and how Visual Studio uses this Dockerfile to build your images for faster debugging.

# This stage is used when running from VS in fast mode (Default for Debug configuration)
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

USER root
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
USER $APP_UID


# This stage is used to build the service project
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["Directory.Packages.props", "./"]
COPY ["src/Services/EcommerceDDD.PaymentProcessing/EcommerceDDD.PaymentProcessing.csproj", "src/Services/EcommerceDDD.PaymentProcessing/"]
COPY ["src/Core/EcommerceDDD.Core.Infrastructure/EcommerceDDD.Core.Infrastructure.csproj", "src/Core/EcommerceDDD.Core.Infrastructure/"]
COPY ["src/Core/EcommerceDDD.Core/EcommerceDDD.Core.csproj", "src/Core/EcommerceDDD.Core/"]
COPY ["src/Crosscutting/EcommerceDDD.ServiceClients/EcommerceDDD.ServiceClients.csproj", "src/Crosscutting/EcommerceDDD.ServiceClients/"]
RUN dotnet restore "./src/Services/EcommerceDDD.PaymentProcessing/EcommerceDDD.PaymentProcessing.csproj"
COPY . .
WORKDIR "/src/src/Services/EcommerceDDD.PaymentProcessing"
RUN dotnet publish "./EcommerceDDD.PaymentProcessing.csproj" -c $BUILD_CONFIGURATION --no-restore -o /app/publish /p:UseAppHost=false

# This stage is used in production or when running from VS in regular mode (Default when not using the Debug configuration)
FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "EcommerceDDD.PaymentProcessing.dll"]