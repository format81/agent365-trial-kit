// Fictional employee directory for "Prism Industries".
// Everything here is synthetic demo data — no real people or emails.

export interface Employee {
  id: string;
  name: string;
  email: string;
  department: string;
  title: string;
  manager: string;
}

export const EMPLOYEES: Employee[] = [
  {
    id: 'E001', name: 'Antonio Formato',
    email: 'antonio@prismindustries.com',
    department: 'IT Operations', title: 'Head of IT',
    manager: 'Sarah Chen'
  },
  {
    id: 'E002', name: 'Sarah Chen',
    email: 'sarah.chen@prismindustries.com',
    department: 'Executive', title: 'CEO', manager: ''
  },
  {
    id: 'E003', name: 'Marco Rossi',
    email: 'marco.rossi@prismindustries.com',
    department: 'Legal', title: 'Head of Compliance',
    manager: 'Sarah Chen'
  },
  {
    id: 'E004', name: 'Aiko Tanaka',
    email: 'aiko.tanaka@prismindustries.com',
    department: 'Engineering', title: 'Senior Engineer',
    manager: 'Marco Rossi'
  },
  {
    id: 'E005', name: 'Priya Sharma',
    email: 'priya.sharma@prismindustries.com',
    department: 'Sales', title: 'Account Executive',
    manager: "James O'Brien"
  },
  {
    id: 'E006', name: 'Liam Walsh',
    email: 'liam.walsh@prismindustries.com',
    department: 'Customer Success', title: 'CSM',
    manager: 'Sarah Chen'
  },
  {
    id: 'E007', name: "James O'Brien",
    email: 'james.obrien@prismindustries.com',
    department: 'Sales', title: 'VP Sales',
    manager: 'Sarah Chen'
  },
  {
    id: 'E008', name: 'Daniela Costa',
    email: 'daniela.costa@prismindustries.com',
    department: 'Finance', title: 'Financial Controller',
    manager: 'Marco Rossi'
  }
];
