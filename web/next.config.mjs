/** @type {import('next').NextConfig} */
const nextConfig = {
  // Needed by the Dockerfile: emits a self-contained server bundle.
  output: 'standalone',
};

export default nextConfig;
