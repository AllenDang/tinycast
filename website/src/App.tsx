import { Nav } from "./components/nav";
import { Hero } from "./components/hero";
import { Features } from "./components/features";
import { Ethos } from "./components/ethos";
import { Install } from "./components/install";
import { Footer } from "./components/footer";

function App() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Features />
        <Ethos />
        <Install />
      </main>
      <Footer />
    </>
  );
}

export default App;
