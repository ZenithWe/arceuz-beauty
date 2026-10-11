import "./styles/tokens.css";
import "./globals.css";
export const metadata = { title: "ARCEUZ BEAUTY OS", description: "A inteligência que transforma a gestão do seu salão." };
export default function Root({ children }: { children: React.ReactNode }) {
  return (<html lang="pt-BR" data-theme="dark"><body>{children}</body></html>);
}
