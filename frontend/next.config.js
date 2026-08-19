/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: false,
  output: 'standalone',
  transpilePackages: [
    '@labring/sealos-shared-sdk',
    '@labring/sealos-desktop-sdk',
    '@labring/sealos-tty-client',
    '@xterm/xterm',
    '@xterm/addon-fit'
  ],
  productionBrowserSourceMaps: true,
  webpack(config, { dev }) {
    if (!dev) {
      config.optimization.innerGraph = false;
    }
    return config;
  }
};

module.exports = nextConfig;
