import { Play } from "lucide-react";
import { useState } from "react";
import Lightbox, { type Slide } from "yet-another-react-lightbox";
import Captions from "yet-another-react-lightbox/plugins/captions";
import Video from "yet-another-react-lightbox/plugins/video";
import Zoom from "yet-another-react-lightbox/plugins/zoom";
import "yet-another-react-lightbox/styles.css";
import "yet-another-react-lightbox/plugins/captions.css";
import { galleryItems, type GalleryItem } from "../data/gallery";
import { Reveal } from "./ui/reveal";
import { Section } from "./ui/section";

// Everything in `public/` is served under the Vite base path.
const asset = (name: string) => `${import.meta.env.BASE_URL}${name}`;

// The grid thumbnail: an explicit thumb, else a video's poster, else the image.
const tileImage = (item: GalleryItem) =>
  asset(item.thumb ?? (item.type === "video" ? (item.poster ?? item.src) : item.src));

// One gallery item → one lightbox slide. Images carry title/description for the
// Captions plugin; videos use the Video plugin's `sources` shape.
function toSlide(item: GalleryItem): Slide {
  if (item.type === "video") {
    return {
      type: "video",
      poster: item.poster ? asset(item.poster) : undefined,
      width: item.width,
      height: item.height,
      title: item.title,
      description: item.caption,
      sources: [{ src: asset(item.src), type: "video/mp4" }],
    };
  }
  return {
    src: asset(item.src),
    title: item.title,
    description: item.caption,
    width: item.width,
    height: item.height,
  };
}

export function Gallery() {
  const [index, setIndex] = useState(-1);
  const slides = galleryItems.map(toSlide);

  return (
    <Section
      id="gallery"
      eyebrow="Tinycast in action"
      title="See it in motion."
      intro="A palette that stays out of your way — until you need it."
    >
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {galleryItems.map((item, i) => (
          <Reveal key={`${item.title}-${i}`} delay={i * 60}>
            <button
              type="button"
              onClick={() => setIndex(i)}
              className="group flex h-full w-full flex-col gap-3 rounded-2xl bg-ink/40 p-3 text-left shadow-key transition-shadow duration-200 hover:shadow-key-hover"
            >
              <figure className="relative aspect-video w-full overflow-hidden rounded-xl">
                <img
                  src={tileImage(item)}
                  alt={item.title}
                  className="block size-full object-cover transition-transform duration-300 group-hover:scale-[1.02]"
                  loading="lazy"
                  decoding="async"
                />
                {item.type === "video" && (
                  <span className="absolute inset-0 flex items-center justify-center">
                    <span className="flex size-12 items-center justify-center rounded-full bg-black/40 text-white shadow-highlight backdrop-blur-sm">
                      <Play size={20} fill="currentColor" />
                    </span>
                  </span>
                )}
              </figure>
              <div className="px-1 pb-1">
                <h3 className="text-body-lg font-medium text-white">
                  {item.title}
                </h3>
                <p className="mt-1 text-body text-ash">{item.caption}</p>
              </div>
            </button>
          </Reveal>
        ))}
      </div>

      <Lightbox
        open={index >= 0}
        index={index}
        close={() => setIndex(-1)}
        slides={slides}
        plugins={[Video, Captions, Zoom]}
        controller={{ closeOnBackdropClick: true }}
      />
    </Section>
  );
}
