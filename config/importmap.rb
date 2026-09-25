# React is loaded from esm.sh through the import map: no Node, no bundler, no
# node_modules in the runtime image.
pin "application"
pin "react", to: "https://esm.sh/react@19.1.1"
pin "react-dom/client", to: "https://esm.sh/react-dom@19.1.1/client"
pin "htm", to: "https://esm.sh/htm@3.1.1"
pin_all_from "app/javascript/islands", under: "islands"
