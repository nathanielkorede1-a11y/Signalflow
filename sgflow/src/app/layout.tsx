import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = { title: "SignalFlow — Trading intelligence, delivered", description: "A clear, disciplined workspace for trading signals." };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="en"><body>{children}</body></html>; }
