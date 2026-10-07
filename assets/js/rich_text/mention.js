// Menciones con «@» (RF-TAB-004): sugiere a las personas del curso. El
// servidor guarda el ID y el nombre (Amauta.RichText, nodo «mention»).
import Mention from "@tiptap/extension-mention"
import {menu} from "./slash_menu"

const normalize = (text) => text.normalize("NFD").replace(/\p{Mn}/gu, "").toLowerCase()

export const MentionPeople = (people) =>
  Mention.configure({
    HTMLAttributes: {class: "rich-mention"},
    renderText: ({node}) => `@${node.attrs.label}`,
    suggestion: {
      char: "@",
      items: ({query}) =>
        people.filter((person) => normalize(person.label).includes(normalize(query))).slice(0, 8),
      render: menu("rich-mention-option"),
    },
  })
