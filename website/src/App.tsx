import { Nav } from "./components/nav";
import { Hero } from "./components/hero";
import { Features } from "./components/features";
import { Compare } from "./components/compare";
import { Switch } from "./components/switch";
import { Ethos } from "./components/ethos";
import { Install } from "./components/install";
import { Footer } from "./components/footer";
import { ScrollTop } from "./components/ui/scroll-top";

function App() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Features />
        <Compare />
        <Switch />
        <Ethos />
        <Install />
      </main>
      <Footer />
      <ScrollTop />
    </>
  );
}

export default App;
