import type { Metadata } from 'next';
import './globals.css';
import { SessionProvider } from '../lib/session';
import { TopBar } from './topbar';

export const metadata: Metadata = {
  title: 'Sanjeevani AI — Staff Console',
  description: 'Doctor queue and hospital admin dashboards',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <SessionProvider>
          <TopBar />
          <main>{children}</main>
        </SessionProvider>
      </body>
    </html>
  );
}
